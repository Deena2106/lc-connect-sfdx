import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import isGuest from '@salesforce/user/isGuest';
import getAmbassador from '@salesforce/apex/LC_DirectoryController.getAmbassador';
import { avatarStyle, goToChat, initials, queryParam, reduceError, rememberUtm, replyTimeLabel, siteUrl, ROUTES } from 'c/lcUtils';

/**
 * Launched Connect - public ambassador profile page (/ambassador?name=<slug>).
 */
export default class LcAmbassadorProfile extends LightningElement {
    @api safetyNote = 'Chats are monitored by university staff to keep everyone safe. Please don’t share personal contact details.';

    ambassador;
    notFound = false;
    isLoading = true;
    error;
    slug;

    @wire(CurrentPageReference)
    setPageRef(pageRef) {
        const fromState = pageRef && pageRef.state ? pageRef.state.name : null;
        const slug = fromState || queryParam('name');
        if (slug && slug !== this.slug) {
            this.slug = slug;
            this.load();
        } else if (!slug) {
            this.isLoading = false;
            this.notFound = true;
        }
    }

    connectedCallback() {
        rememberUtm();
    }

    async load() {
        this.isLoading = true;
        this.error = undefined;
        try {
            this.ambassador = await getAmbassador({ slugOrId: this.slug });
            this.notFound = !this.ambassador;
        } catch (e) {
            this.error = reduceError(e);
        } finally {
            this.isLoading = false;
        }
    }

    get directoryUrl() {
        return siteUrl(ROUTES.home);
    }

    get guidelinesUrl() {
        return siteUrl(ROUTES.guidelines);
    }

    get avatarStyle() {
        return avatarStyle(this.ambassador.displayName, 112);
    }

    get initials() {
        return initials(this.ambassador.displayName);
    }

    get hasInterests() {
        return this.ambassador && this.ambassador.interests && this.ambassador.interests.length > 0;
    }

    get replyLabel() {
        return replyTimeLabel(this.ambassador.avgResponseMinutes) || 'Ambassadors reply as soon as they can.';
    }

    get ctaLabel() {
        return isGuest ? `Sign up to chat with ${this.ambassador.displayName}` : `Message ${this.ambassador.displayName}`;
    }

    get facts() {
        const a = this.ambassador;
        const home = [a.homeCity, a.homeCountry].filter(Boolean).join(', ');
        return [
            { label: 'Studies', value: a.programme || a.subjectArea },
            { label: 'Level', value: [a.studyLevel, a.yearOfStudy].filter(Boolean).join(' · ') },
            { label: 'From', value: home },
            { label: 'Languages', value: (a.languages || []).join(', ') },
            { label: 'Accommodation', value: a.livedInHalls ? 'Has lived in university halls' : null }
        ].filter((f) => f.value);
    }

    handleChat() {
        goToChat(this.ambassador.slug, 'Profile', isGuest);
    }
}