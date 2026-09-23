import { LightningElement, api } from 'lwc';
import isGuest from '@salesforce/user/isGuest';
import getViewer from '@salesforce/apex/LC_ProfileController.getViewer';
import listMyConversations from '@salesforce/apex/LC_ChatController.listMyConversations';
import startConversation from '@salesforce/apex/LC_ChatController.startConversation';
import askAdmissions from '@salesforce/apex/LC_ChatController.askAdmissions';
import { queryParam, reduceError, siteUrl, ROUTES } from 'c/lcUtils';

const LIST_REFRESH_SECONDS = 30;

/**
 * Launched Connect - prospect chat workspace (My Chats page, members only).
 * URL options: ?ambassador=<slug>&origin=Profile starts (or re-opens) a chat; ?c=<conversationId> opens one.
 */
export default class LcChatWorkspace extends LightningElement {
    @api monitorNotice = 'Messages are monitored by Launched EDX University staff to keep everyone safe.';
    @api link1Label = 'Book an open day';
    @api link1Url;
    @api link2Label = 'Accommodation guide';
    @api link2Url;
    @api link3Label = 'Fees and funding';
    @api link3Url;

    conversations = [];
    selectedId;
    isLoading = true;
    error;
    showAsk = false;
    listTimer;

    get directoryUrl() {
        return siteUrl(ROUTES.home);
    }

    get layoutClass() {
        return this.selectedId ? 'ws ws_thread-open' : 'ws';
    }

    async connectedCallback() {
        if (isGuest) {
            window.location.assign(siteUrl(ROUTES.login, { startURL: window.location.pathname + window.location.search }));
            return;
        }
        try {
            const viewer = await getViewer();
            if (viewer.isAmbassador) {
                window.location.assign(siteUrl(ROUTES.inbox));
                return;
            }
            const ambassador = queryParam('ambassador');
            const origin = queryParam('origin') || 'Profile';
            if (!viewer.profileComplete) {
                window.location.assign(siteUrl(ROUTES.completeProfile, { ambassador, origin }));
                return;
            }
            if (ambassador) {
                this.selectedId = await startConversation({ ambassador, origin });
                this.cleanUrl();
            } else if (queryParam('c')) {
                this.selectedId = queryParam('c');
            }
            await this.refreshList();
            if (!this.selectedId && this.conversations.length && window.matchMedia('(min-width: 901px)').matches) {
                this.selectedId = this.conversations[0].id;
            }
        } catch (e) {
            this.error = reduceError(e);
        } finally {
            this.isLoading = false;
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.listTimer = setInterval(() => {
            if (!document.hidden) {
                this.refreshList();
            }
        }, LIST_REFRESH_SECONDS * 1000);
    }

    disconnectedCallback() {
        clearInterval(this.listTimer);
    }

    refreshList = async () => {
        try {
            this.conversations = await listMyConversations();
        } catch (e) {
            this.error = reduceError(e);
        }
    };

    cleanUrl() {
        try {
            window.history.replaceState({}, '', siteUrl(ROUTES.messages, { c: this.selectedId }));
        } catch (e) {
            // Non-critical.
        }
    }

    handleSelect(event) {
        this.selectedId = event.detail.id;
        this.cleanUrl();
    }

    handleBack() {
        this.selectedId = undefined;
    }

    openAsk() {
        this.showAsk = true;
    }

    closeAsk() {
        this.showAsk = false;
    }

    async submitAsk(event) {
        this.showAsk = false;
        this.error = undefined;
        try {
            this.selectedId = await askAdmissions({ subCategory: event.detail.subCategory, question: event.detail.text });
            await this.refreshList();
            this.cleanUrl();
        } catch (e) {
            this.error = reduceError(e);
        }
    }
}
