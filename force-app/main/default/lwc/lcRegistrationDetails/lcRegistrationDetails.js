import { LightningElement, api } from 'lwc';
import isGuest from '@salesforce/user/isGuest';
import getRegistrationContext from '@salesforce/apex/LC_ProfileController.getRegistrationContext';
import completeRegistration from '@salesforce/apex/LC_ProfileController.completeRegistration';
import getViewer from '@salesforce/apex/LC_ProfileController.getViewer';
import { COUNTRIES, queryParam, readUtm, reduceError, siteUrl, ROUTES } from 'c/lcUtils';

/**
 * Launched Connect - "About you" step (Complete Profile page, members only).
 * If the profile is already complete, sends the user straight on.
 */
export default class LcRegistrationDetails extends LightningElement {
    @api heading = 'Tell us a little about yourself';
    @api universityName = 'Launched EDX University';

    form = {
        firstName: '',
        lastName: '',
        country: '',
        birthdate: null,
        programmeId: '',
        termId: '',
        acceptGuidelines: false,
        marketingOptIn: false
    };
    programmeOptions = [];
    termOptions = [];
    countryOptions = COUNTRIES;
    guidelinesVersion;
    isLoading = true;
    isSaving = false;
    ready = false;
    error;

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
            if (viewer.profileComplete) {
                this.continueOn();
                return;
            }
            const ctx = await getRegistrationContext();
            this.form = {
                ...this.form,
                firstName: ctx.firstName || '',
                lastName: ctx.lastName || '',
                country: ctx.country || '',
                birthdate: ctx.birthdate || null
            };
            this.programmeOptions = ctx.programmes;
            this.termOptions = ctx.terms;
            this.guidelinesVersion = ctx.guidelinesVersion;
            this.ready = true;
        } catch (e) {
            this.error = reduceError(e);
        } finally {
            this.isLoading = false;
        }
    }

    get today() {
        return new Date().toISOString().slice(0, 10);
    }

    get guidelinesUrl() {
        return siteUrl(ROUTES.guidelines);
    }

    get guidelinesLabel() {
        return 'I agree to the Launched Connect community guidelines and understand chats are monitored by university staff to keep everyone safe.';
    }

    get marketingLabel() {
        return `Keep me updated by email about courses, events and applying to ${this.universityName} (optional, you can unsubscribe at any time).`;
    }

    get submitLabel() {
        return queryParam('ambassador') ? 'Create account and start chatting' : 'Save and continue';
    }

    handleChange(event) {
        const { name, type } = event.target;
        const value = type === 'checkbox' ? event.target.checked : event.detail.value;
        this.form = { ...this.form, [name]: value };
    }

    async handleSubmit(event) {
        event.preventDefault();
        const fields = [...this.template.querySelectorAll('lightning-input, lightning-combobox')];
        const valid = fields.reduce((ok, f) => f.reportValidity() && ok, true);
        if (!valid) {
            return;
        }
        this.isSaving = true;
        this.error = undefined;
        const utm = readUtm();
        const ambassador = queryParam('ambassador');
        try {
            await completeRegistration({
                input: {
                    ...this.form,
                    ambassador,
                    source: queryParam('origin') || (ambassador ? 'Profile' : 'Directory'),
                    utmSource: utm.utm_source,
                    utmMedium: utm.utm_medium,
                    utmCampaign: utm.utm_campaign
                }
            });
            this.continueOn();
        } catch (e) {
            this.error = reduceError(e);
            this.isSaving = false;
        }
    }

    continueOn() {
        const ambassador = queryParam('ambassador');
        if (ambassador) {
            window.location.assign(siteUrl(ROUTES.messages, { ambassador, origin: queryParam('origin') || 'Profile' }));
        } else {
            window.location.assign(siteUrl(ROUTES.messages));
        }
    }
}
