import { LightningElement, api } from 'lwc';
import getThread from '@salesforce/apex/LC_ChatController.getThread';
import sendMessage from '@salesforce/apex/LC_ChatController.sendMessage';
import closeConversation from '@salesforce/apex/LC_ChatController.closeConversation';
import reportConcern from '@salesforce/apex/LC_ChatController.reportConcern';
import referToAdmissions from '@salesforce/apex/LC_ChatController.referToAdmissions';
import logTime from '@salesforce/apex/LC_AmbassadorController.logTime';
import { avatarStyle, formatTime, initials, reduceError, uuid } from 'c/lcUtils';

const MAX_POLL_SECONDS = 60;
const HIDDEN_POLL_SECONDS = 30;

/**
 * Launched Connect - one conversation: messages, composer and actions (child component).
 * Polls for new messages while open (lightning/empApi is not available on Experience Cloud sites).
 * Fires "conversationchange" after the user sends or closes, and "back" on mobile.
 */
export default class LcChatThread extends LightningElement {
    @api showBack = false;
    @api monitorNotice = 'Messages are monitored by university staff to keep everyone safe.';

    _conversationId;
    conversation;
    role;
    canSend = false;
    lockedReason;
    prospectCountry;
    prospectInterest;
    messages = [];
    since;
    basePoll = 5;
    currentPoll = 5;
    timer;
    connected = false;
    isLoading = false;
    isBusy = false;
    error;
    noticeText;
    draft = '';
    showReport = false;
    showRefer = false;
    logMinutes = '10';
    scrollPending = false;

    @api
    get conversationId() {
        return this._conversationId;
    }
    set conversationId(value) {
        if (value !== this._conversationId) {
            this._conversationId = value;
            this.resetState();
            if (this.connected && value) {
                this.loadInitial();
            }
        }
    }

    connectedCallback() {
        this.connected = true;
        this.visibilityHandler = () => {
            if (!document.hidden && this._conversationId) {
                this.currentPoll = this.basePoll;
                this.schedule(0);
            }
        };
        document.addEventListener('visibilitychange', this.visibilityHandler);
        if (this._conversationId) {
            this.loadInitial();
        }
    }

    disconnectedCallback() {
        this.connected = false;
        this.stopPolling();
        document.removeEventListener('visibilitychange', this.visibilityHandler);
    }

    renderedCallback() {
        if (this.scrollPending && this.refs.scroller) {
            this.refs.scroller.scrollTop = this.refs.scroller.scrollHeight;
            this.scrollPending = false;
        }
    }

    // ------------------------------------------------------------ getters
    get isAmbassador() {
        return this.role === 'Ambassador';
    }
    get isLocked() {
        return !this.canSend;
    }
    get canClose() {
        return this.role === 'Prospect' && this.conversation && this.conversation.status !== 'Closed';
    }
    get sendDisabled() {
        return this.isLocked || !this.draft.trim();
    }
    get title() {
        if (!this.conversation) {
            return '';
        }
        if (this.isAmbassador) {
            return this.conversation.counterpartName;
        }
        return this.conversation.channelType === 'Staff'
            ? this.conversation.counterpartName
            : `${this.conversation.counterpartName} · Student ambassador`;
    }
    get subtitle() {
        if (!this.conversation) {
            return '';
        }
        if (this.isAmbassador) {
            return [this.prospectCountry, this.prospectInterest ? `Interested in ${this.prospectInterest}` : null].filter(Boolean).join(' · ');
        }
        return this.conversation.counterpartSubtitle || '';
    }
    get avatarStyle() {
        return avatarStyle(this.conversation ? this.conversation.counterpartName : '', 40);
    }
    get initials() {
        return initials(this.conversation ? this.conversation.counterpartName : '');
    }
    get composePlaceholder() {
        if (this.isLocked) {
            return this.lockedReason || 'This chat is closed.';
        }
        return this.conversation ? `Message ${this.conversation.counterpartName}…` : 'Write a message…';
    }
    get minuteOptions() {
        return ['5', '10', '15', '20', '30', '45', '60'].map((m) => ({ label: `${m} minutes`, value: m }));
    }
    get displayMessages() {
        return this.messages.map((m) => {
            const isSystem = m.senderType === 'System';
            const mine = m.mine;
            let bubbleClass = 'thread__bubble';
            if (isSystem) {
                bubbleClass += ' thread__bubble_system';
            } else if (mine) {
                bubbleClass += ' thread__bubble_mine';
            } else if (m.senderType === 'Staff') {
                bubbleClass += ' thread__bubble_staff';
            }
            if (m.visibility && m.visibility !== 'Visible') {
                bubbleClass += ' thread__bubble_held';
            }
            let status = formatTime(m.sentAt);
            if (m.pending) {
                status = 'Sending…';
            } else if (m.failed) {
                status = 'Not sent';
            }
            return {
                ...m,
                key: m.id || m.clientMessageId,
                wrapClass: isSystem ? 'thread__wrap thread__wrap_system' : mine ? 'thread__wrap thread__wrap_mine' : 'thread__wrap',
                bubbleClass,
                meta: isSystem ? status : `${mine ? 'You' : m.senderName || ''} · ${status}`
            };
        });
    }

    // ------------------------------------------------------------ loading & polling
    resetState() {
        this.stopPolling();
        this.conversation = undefined;
        this.messages = [];
        this.since = undefined;
        this.error = undefined;
        this.noticeText = undefined;
    }

    async loadInitial() {
        const id = this._conversationId;
        this.isLoading = true;
        try {
            const t = await getThread({ conversationId: id, since: null });
            if (id !== this._conversationId) {
                return;
            }
            this.applyThread(t, true);
            this.scrollPending = true;
            this.schedule(this.basePoll);
        } catch (e) {
            this.error = reduceError(e);
        } finally {
            this.isLoading = false;
        }
    }

    async poll() {
        const id = this._conversationId;
        if (!id || !this.connected) {
            return;
        }
        try {
            const t = await getThread({ conversationId: id, since: this.since });
            if (id !== this._conversationId) {
                return;
            }
            const gotNew = this.applyThread(t, false);
            this.currentPoll = gotNew ? this.basePoll : Math.min(Math.round(this.currentPoll * 1.5), MAX_POLL_SECONDS);
            if (gotNew) {
                this.scrollPending = true;
            }
        } catch (e) {
            this.currentPoll = Math.min(this.currentPoll * 2, MAX_POLL_SECONDS);
        }
        this.schedule(document.hidden ? HIDDEN_POLL_SECONDS : this.currentPoll);
    }

    schedule(seconds) {
        this.stopPolling();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.timer = setTimeout(() => this.poll(), seconds * 1000);
    }

    stopPolling() {
        if (this.timer) {
            clearTimeout(this.timer);
            this.timer = undefined;
        }
    }

    /** Merges a thread response. Returns true if anything new arrived. */
    applyThread(t, replace) {
        this.conversation = t.conversation;
        this.role = t.role;
        this.canSend = t.canSend;
        this.lockedReason = t.lockedReason;
        this.prospectCountry = t.prospectCountry;
        this.prospectInterest = t.prospectInterest;
        this.basePoll = t.pollSeconds || 5;
        this.since = t.serverTime;
        if (replace) {
            this.messages = t.messages;
            this.currentPoll = this.basePoll;
            return t.messages.length > 0;
        }
        if (!t.messages.length) {
            return false;
        }
        const list = [...this.messages];
        let added = false;
        t.messages.forEach((incoming) => {
            const idx = list.findIndex(
                (m) => m.id === incoming.id || (incoming.clientMessageId && m.clientMessageId === incoming.clientMessageId)
            );
            if (idx >= 0) {
                list[idx] = incoming;
            } else {
                list.push(incoming);
                added = true;
            }
        });
        this.messages = list;
        return added;
    }

    // ------------------------------------------------------------ sending
    handleDraft(event) {
        this.draft = event.target.value;
    }

    handleKeydown(event) {
        if (event.key === 'Enter' && !event.shiftKey) {
            event.preventDefault();
            this.handleSend(event);
        }
    }

    handleSend(event) {
        event.preventDefault();
        const body = this.draft.trim();
        if (!body || this.isLocked) {
            return;
        }
        const clientMessageId = uuid();
        this.messages = [
            ...this.messages,
            { clientMessageId, body, mine: true, senderType: this.role, pending: true, sentAt: new Date().toISOString() }
        ];
        this.draft = '';
        this.refs.composer.value = '';
        this.scrollPending = true;
        this.deliver(clientMessageId, body);
    }

    retry(event) {
        const key = event.currentTarget.dataset.key;
        const msg = this.messages.find((m) => m.clientMessageId === key);
        if (msg) {
            this.messages = this.messages.map((m) => (m.clientMessageId === key ? { ...m, failed: false, pending: true } : m));
            this.deliver(key, msg.body);
        }
    }

    async deliver(clientMessageId, body) {
        this.error = undefined;
        this.noticeText = undefined;
        try {
            const res = await sendMessage({ conversationId: this._conversationId, body, clientMessageId });
            this.messages = this.messages.map((m) => (m.clientMessageId === clientMessageId ? res.message : m));
            if (res.held) {
                this.noticeText = res.notice;
            }
            this.currentPoll = this.basePoll;
            this.schedule(this.basePoll);
            this.dispatchEvent(new CustomEvent('conversationchange'));
        } catch (e) {
            this.error = reduceError(e);
            this.messages = this.messages.map((m) =>
                m.clientMessageId === clientMessageId ? { ...m, pending: false, failed: true } : m
            );
        }
    }

    // ------------------------------------------------------------ actions
    openReport() {
        this.showReport = true;
    }
    openRefer() {
        this.showRefer = true;
    }
    closeModals() {
        this.showReport = false;
        this.showRefer = false;
    }

    async submitReport(event) {
        this.closeModals();
        await this.act(async () => {
            await reportConcern({
                conversationId: this._conversationId,
                messageId: null,
                reason: event.detail.reason,
                details: event.detail.details
            });
            this.noticeText = 'Thank you. The university team has been told and will look at this chat.';
        });
    }

    async submitRefer(event) {
        this.closeModals();
        await this.act(async () => {
            await referToAdmissions({
                conversationId: this._conversationId,
                subCategory: event.detail.subCategory,
                note: event.detail.text
            });
            this.noticeText = 'Referred. The admissions team will reply to the student in a new chat.';
            this.poll();
        });
    }

    async handleClose() {
        await this.act(async () => {
            await closeConversation({ conversationId: this._conversationId });
            await this.loadInitial();
            this.dispatchEvent(new CustomEvent('conversationchange'));
        });
    }

    handleMinutes(event) {
        this.logMinutes = event.detail.value;
    }

    async handleLogTime() {
        await this.act(async () => {
            await logTime({
                conversationId: this._conversationId,
                minutes: parseInt(this.logMinutes, 10),
                activityType: 'Chat',
                notes: null
            });
            this.noticeText = `${this.logMinutes} minutes logged.`;
        });
    }

    handleBack() {
        this.dispatchEvent(new CustomEvent('back'));
    }

    async act(fn) {
        this.isBusy = true;
        this.error = undefined;
        try {
            await fn();
        } catch (e) {
            this.error = reduceError(e);
        } finally {
            this.isBusy = false;
        }
    }
}
