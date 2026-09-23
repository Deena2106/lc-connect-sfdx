import { LightningElement, api } from 'lwc';

/**
 * Launched Connect - safety guidance, admissions route and useful links (child component).
 * Fires "askadmissions".
 */
export default class LcChatSidePanel extends LightningElement {
    @api safetyText =
        "Keep chats on this site. Don't share phone numbers, social media or addresses. If anything makes you uncomfortable, use Report.";
    @api officialText = "Ambassadors can't answer questions about your application, offers or fees.";
    @api link1Label;
    @api link1Url;
    @api link2Label;
    @api link2Url;
    @api link3Label;
    @api link3Url;

    get links() {
        return [
            { label: this.link1Label, url: this.link1Url },
            { label: this.link2Label, url: this.link2Url },
            { label: this.link3Label, url: this.link3Url }
        ].filter((l) => l.label && l.url);
    }

    get hasLinks() {
        return this.links.length > 0;
    }

    handleAsk() {
        this.dispatchEvent(new CustomEvent('askadmissions'));
    }
}
