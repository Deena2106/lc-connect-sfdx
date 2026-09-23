import { LightningElement, api } from 'lwc';
import { avatarStyle, initials, replyTimeLabel, siteUrl, ROUTES } from 'c/lcUtils';

/**
 * Launched Connect - ambassador card (used by the directory and the login page preview).
 * Fires "ask" with detail { slug } when "Ask a question" is clicked.
 */
export default class LcAmbassadorCard extends LightningElement {
    @api ambassador = {};
    /** 'card' (default) or 'preview' (larger, shows bio, no buttons) */
    @api variant = 'card';

    get isPreview() {
        return this.variant === 'preview';
    }

    get cardClass() {
        return this.isPreview ? 'lc-card card card_preview' : 'lc-card card';
    }

    get avatarStyle() {
        return avatarStyle(this.ambassador.displayName, this.isPreview ? 96 : 72);
    }

    get initials() {
        return initials(this.ambassador.displayName);
    }

    get subtitle() {
        const parts = [this.ambassador.programme || this.ambassador.subjectArea, this.ambassador.yearOfStudy].filter(Boolean);
        return parts.join(' · ');
    }

    get locationLine() {
        const parts = [this.ambassador.homeCity, this.ambassador.homeCountry].filter(Boolean).join(', ');
        const langs = (this.ambassador.languages || []).join(', ');
        return [parts, langs ? `Speaks ${langs}` : null].filter(Boolean).join(' · ');
    }

    get tags() {
        const list = this.ambassador.interests || [];
        return this.isPreview ? list : list.slice(0, 3);
    }

    get replyLabel() {
        return replyTimeLabel(this.ambassador.avgResponseMinutes);
    }

    get profileUrl() {
        return siteUrl(ROUTES.profile, { name: this.ambassador.slug });
    }

    handleAsk() {
        this.dispatchEvent(new CustomEvent('ask', { detail: { slug: this.ambassador.slug } }));
    }
}
