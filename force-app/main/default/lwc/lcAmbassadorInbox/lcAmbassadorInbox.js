import { LightningElement } from 'lwc';
import isGuest from '@salesforce/user/isGuest';
import getInbox from '@salesforce/apex/LC_AmbassadorController.getInbox';
import setAvailability from '@salesforce/apex/LC_AmbassadorController.setAvailability';
import { reduceError, siteUrl, ROUTES } from 'c/lcUtils';

const REFRESH_SECONDS = 30;

/**
 * Launched Connect - ambassador inbox (Ambassador Inbox page, Ambassadors audience).
 * Waiting conversations are shown first, oldest first.
 */
export default class LcAmbassadorInbox extends LightningElement {
    stats = { awaitingReply: 0 };
    conversations = [];
    displayName = '';
    available = true;
    selectedId;
    isLoading = true;
    error;
    timer;

    get layoutClass() {
        return this.selectedId ? 'amb amb_thread-open' : 'amb';
    }
    get profileUrl() {
        return siteUrl(ROUTES.myProfile);
    }
    get guidelinesUrl() {
        return siteUrl(ROUTES.guidelines);
    }
    get avgReply() {
        const m = this.stats.avgResponseMinutes;
        if (m === null || m === undefined) {
            return '–';
        }
        return m < 60 ? `${m}m` : `${Math.floor(m / 60)}h ${m % 60}m`;
    }
    get hoursLabel() {
        const used = this.stats.hoursThisMonth || 0;
        return this.stats.monthlyAllowance ? `${used}h of ${this.stats.monthlyAllowance}h allowance` : `${used}h logged`;
    }

    connectedCallback() {
        if (isGuest) {
            window.location.assign(siteUrl(ROUTES.login, { startURL: siteUrl(ROUTES.inbox) }));
            return;
        }
        this.refresh();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.timer = setInterval(() => {
            if (!document.hidden) {
                this.refresh();
            }
        }, REFRESH_SECONDS * 1000);
    }

    disconnectedCallback() {
        clearInterval(this.timer);
    }

    refresh = async () => {
        try {
            const res = await getInbox();
            this.stats = res;
            this.displayName = res.displayName;
            this.available = res.availableForChat;
            this.conversations = this.sort(res.conversations || []);
            this.error = undefined;
        } catch (e) {
            const message = reduceError(e);
            if (message.indexOf('for student ambassadors') >= 0) {
                window.location.assign(siteUrl(ROUTES.messages));
                return;
            }
            this.error = message;
        } finally {
            this.isLoading = false;
        }
    };

    /** Waiting first (longest wait at the top), then most recent. */
    sort(list) {
        const waiting = (c) => c.status !== 'Closed' && c.lastMessageBy === 'Prospect';
        return [...list].sort((a, b) => {
            if (waiting(a) !== waiting(b)) {
                return waiting(a) ? -1 : 1;
            }
            if (waiting(a)) {
                return Number(b.waitingHours || 0) - Number(a.waitingHours || 0);
            }
            return new Date(b.lastMessageAt || 0) - new Date(a.lastMessageAt || 0);
        });
    }

    async handleAvailability(event) {
        const value = event.target.checked;
        try {
            await setAvailability({ available: value });
            this.available = value;
        } catch (e) {
            this.error = reduceError(e);
        }
    }

    handleSelect(event) {
        this.selectedId = event.detail.id;
    }

    handleBack() {
        this.selectedId = undefined;
        this.refresh();
    }
}
