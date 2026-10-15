import { LightningElement, api } from 'lwc';
import isGuest from '@salesforce/user/isGuest';
import getRegistrationContext from '@salesforce/apex/LC_ProfileController.getRegistrationContext';
import completeRegistration from '@salesforce/apex/LC_ProfileController.completeRegistration';
import getViewer from '@salesforce/apex/LC_ProfileController.getViewer';
import saveGuidelinesAcceptance from '@salesforce/apex/LC_ProfileController.saveGuidelinesAcceptance';
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
    guidelinesAccepted = false;
    showGuidelines = false;
    pendingRegistration = false;

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
            console.log('Error loading registration context', e);
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
        if (name === 'birthdate') {
            event.target.setCustomValidity('');
            event.target.reportValidity();
            this.error = undefined;
        }
    }

    async saveAndContinueRegistration() {
        this.isSaving = true;
        this.error = undefined;
        const utm = readUtm();
        const ambassador = queryParam('ambassador');
        try {
            await completeRegistration({
                input: {
                    ...this.form,
                    acceptGuidelines: true,
                    ambassador,
                    source:
                        queryParam('origin') ||
                        (ambassador ? 'Profile' : 'Directory'),
                    utmSource: utm.utm_source,
                    utmMedium: utm.utm_medium,
                    utmCampaign: utm.utm_campaign
                }
            });
            this.continueOn();
        } catch (e) {
            this.error = reduceError(e);
        } finally {
            this.isSaving = false;
        }
    }

    async handleGuidelinesAccepted(event) {
        if (!event.detail?.accepted) {
            return;
        }

        // Use the current version returned by the server.
        const version = this.guidelinesVersion;

        if (!version || event.detail.version !== version) {
            this.error =
                'The guidelines version has changed. Please refresh and try again.';
            return;
        }

        this.isSaving = true;
        this.error = undefined;

        try {
            await saveGuidelinesAcceptance({ version });

            // Allow the registration form only after Apex succeeds.
            this.guidelinesAccepted = true;
            this.showGuidelines = false;
            if (this.pendingRegistration) {
                this.pendingRegistration = false;
                await this.saveAndContinueRegistration();
            }
        } catch (e) {
            this.error = reduceError(e);
            // Keep the modal open so the student can retry.
        } finally {
            this.isSaving = false;
        }
    }

    // async handleSubmit(event) {
    //     event.preventDefault();

    //     // Do not allow submission before guidelines acceptance.
    //     if (!this.guidelinesAccepted) {
    //         this.error = 'Please read and accept the guidelines before continuing.';
    //         this.showGuidelines = true;
    //         return;
    //     }

    //     const fields = [
    //         ...this.template.querySelectorAll(
    //             'lightning-input, lightning-combobox'
    //         )
    //     ];

    //     const valid = fields.reduce(
    //         (ok, field) => field.reportValidity() && ok,
    //         true
    //     );

    //     if (!valid) {
    //         return;
    //     }

    //     if (!this.isAtLeast18(this.form.birthdate)) {
    //         const dobField = this.template.querySelector(
    //             'lightning-input[name="birthdate"]'
    //         );

    //         if (dobField) {
    //             dobField.setCustomValidity(
    //                 'You must be at least 18 years old to register for Launched Connect.'
    //             );
    //             dobField.reportValidity();
    //         }

    //         this.error =
    //             'Registration is available only to people aged 18 or older.';
    //         return;
    //     }

    //     this.isSaving = true;
    //     this.error = undefined;

    //     const utm = readUtm();
    //     const ambassador = queryParam('ambassador');

    //     try {
    //         await completeRegistration({
    //             input: {
    //                 ...this.form,
    //                 acceptGuidelines: true,
    //                 ambassador,
    //                 source:
    //                     queryParam('origin') ||
    //                     (ambassador ? 'Profile' : 'Directory'),
    //                 utmSource: utm.utm_source,
    //                 utmMedium: utm.utm_medium,
    //                 utmCampaign: utm.utm_campaign
    //             }
    //         });

    //         this.continueOn();
    //     } catch (e) {
    //         this.error = reduceError(e);
    //     } finally {
    //         this.isSaving = false;
    //     }
    // }

    async handleSubmit(event) {
        event.preventDefault();

        const fields = [
            ...this.template.querySelectorAll(
                'lightning-input, lightning-combobox'
            )
        ];

        const valid = fields.reduce(
            (ok, field) => field.reportValidity() && ok,
            true
        );

        if (!valid) {
            return;
        }

        if (!this.isAtLeast18(this.form.birthdate)) {
            const dobField = this.template.querySelector(
                'lightning-input[name="birthdate"]'
            );

            if (dobField) {
                dobField.setCustomValidity(
                    'You must be at least 18 years old to register for Launched Connect.'
                );
                dobField.reportValidity();
            }

            this.error =
                'Registration is available only to people aged 18 or older.';
            return;
        }

        this.error = undefined;

        // Show guidelines only after successful form validation.
        if (!this.guidelinesAccepted) {
            this.pendingRegistration = true;
            this.showGuidelines = true;
            return;
        }

        await this.saveAndContinueRegistration();
    }


    continueOn() {
        const ambassador = queryParam('ambassador');
        if (ambassador) {
            window.location.assign(siteUrl(ROUTES.messages, { ambassador, origin: queryParam('origin') || 'Profile' }));
        } else {
            window.location.assign(siteUrl(ROUTES.messages));
        }
    }

    get maxBirthdate() {
        const today = new Date();
        const cutoff = new Date(
            today.getFullYear() - 18,
            today.getMonth(),
            today.getDate()
        );

        const year = cutoff.getFullYear();
        const month = String(cutoff.getMonth() + 1).padStart(2, '0');
        const day = String(cutoff.getDate()).padStart(2, '0');

        return `${year}-${month}-${day}`;
    }
    isAtLeast18(birthdate) {
        if (!birthdate) {
            return false;
        }

        return birthdate <= this.maxBirthdate;
    }
}