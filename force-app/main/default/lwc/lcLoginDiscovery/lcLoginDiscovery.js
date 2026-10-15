import { LightningElement, api, track } from 'lwc';
import startLogin from '@salesforce/apex/LC_AuthController.startLogin';
import verifyLogin from '@salesforce/apex/LC_AuthController.verifyLogin';
import startRegistration from '@salesforce/apex/LC_AuthController.startRegistration';
import verifyRegistration from '@salesforce/apex/LC_AuthController.verifyRegistration';
import getAmbassador from '@salesforce/apex/LC_DirectoryController.getAmbassador';
import { queryParam, reduceError, rememberUtm, siteUrl, ROUTES } from 'c/lcUtils';

const STEP_EMAIL = 'email';
const STEP_NAMES = 'names';
const STEP_CODE = 'code';

/**
 * Launched Connect - passwordless login and sign-up (Login page).
 * Existing users: email -> code. New users: email -> name -> code.
 */
export default class LcLoginDiscovery extends LightningElement {
    @api heading = 'Get started';
    // studentGuidelinesAccepted = false; 
    step = STEP_EMAIL;
    mode; // login | register
    email = '';
    firstName = '';
    lastName = '';
    code = '';
    userId;
    identifier;
    ambassador;
    isBusy = false;
    error;
    info;

    connectedCallback() {
        rememberUtm();
        const slug = queryParam('ambassador');
        if (slug) {
            getAmbassador({ slugOrId: slug })
                .then((a) => {
                    this.ambassador = a;
                })
                .catch(() => {
                    this.ambassador = undefined;
                });
        }
    }

    // ------------------------------------------------------------ getters
    // get showStudentGuidelines() {
    //     return !this.studentGuidelinesAccepted;
    // }
    get isEmailStep() {
        return this.step === STEP_EMAIL;
    }
    get isNamesStep() {
        return this.step === STEP_NAMES;
    }
    get isCodeStep() {
        return this.step === STEP_CODE;
    }
    get step1Class() {
        return 'on';
    }
    get step2Class() {
        return this.step === STEP_CODE ? 'on' : '';
    }
    get step3Class() {
        return '';
    }
    get codePattern() {
        return '[0-9]{6}';
    }
    get guidelinesUrl() {
        return siteUrl(ROUTES.guidelines);
    }

    /** Where to go after login. Defaults to Complete Profile, which then routes on. */
    get startUrl() {
        const requested = queryParam('startURL');
        if (requested && requested.startsWith('/') && !requested.startsWith('//')) {
            return requested;
        }
        return siteUrl(ROUTES.completeProfile);
    }

    // handleStudentGuidelinesAccepted(event) {
    //      const accepted = event.detail?.accepted === true && event.detail?.version === '1.0';
    //      console.log('Student guidelines accepted:', accepted);
    //      if (!accepted) {
    //          this.studentGuidelinesAccepted = false;
    //          this.error = 'Please accept the Student Guidelines to continue.';
    //          return;
    //     }
    //      this.studentGuidelinesAccepted = true;
    //      console.log('Show student guidelines:', this.showStudentGuidelines);
    //      console.log('Student guidelines accepted:', this.studentGuidelinesAccepted);
    //      this.error = undefined;
    //      this.info = undefined;
    // }
    // requireStudentGuidelines() {
    //     if (this.studentGuidelinesAccepted) {
    //         return true;
    //     }
    //     this.error = 'Please accept the Student Guidelines before continuing.';
    //     return false;
    // }

    // ------------------------------------------------------------ handlers
    handleInput(event) {
        this[event.target.name] = (event.target.value || '').trim();
    }

    validate() {
        const inputs = [...this.template.querySelectorAll('lightning-input')];
        return inputs.reduce((ok, input) => input.reportValidity() && ok, true);
    }

    async handleEmail(event) {
        event.preventDefault();
        // if (!this.requireStudentGuidelines()) {
        //     return;
        // }
        if (!this.validate()) {
            return;
        }
        await this.run(async () => {
            const res = await startLogin({ email: this.email });
            this.mode = res.mode;
            this.email = res.email;
            if (res.mode === 'login') {
                this.userId = res.userId;
                this.identifier = res.identifier;
                this.step = STEP_CODE;
            } else {
                this.step = STEP_NAMES;
            }
        });
    }

    async handleRegister(event) {
        event.preventDefault();
        // if (!this.requireStudentGuidelines()) {
        //     return;
        // }
        if (!this.validate()) {
            return;
        }
        await this.run(async () => {
            const res = await startRegistration({ firstName: this.firstName, lastName: this.lastName, email: this.email });
            this.identifier = res.identifier;
            this.step = STEP_CODE;
        });
    }

    async handleVerify(event) {
        event.preventDefault();
        // if (!this.requireStudentGuidelines()) {
        //     return;
        // }
        if (!this.validate()) {
            return;
        }
        await this.run(async () => {
            const redirectUrl =
                this.mode === 'login'
                    ? await verifyLogin({ userId: this.userId, identifier: this.identifier, code: this.code, startUrl: this.startUrl })
                    : await verifyRegistration({ identifier: this.identifier, code: this.code, startUrl: this.startUrl });
            // The returned URL completes the session and then opens startUrl.
            window.location.assign(redirectUrl);
        }, true);
    }

    async handleResend() {
        // if (!this.requireStudentGuidelines()) {
        //     return;
        // }
        this.code = '';
        await this.run(async () => {
            if (this.mode === 'login') {
                const res = await startLogin({ email: this.email });
                this.identifier = res.identifier;
            } else {
                const res = await startRegistration({ firstName: this.firstName, lastName: this.lastName, email: this.email });
                this.identifier = res.identifier;
            }
            this.info = 'We have sent you a new code.';
        });
    }

    startOver() {
        this.step = STEP_EMAIL;
        this.mode = undefined;
        this.code = '';
        this.identifier = undefined;
        this.userId = undefined;
        this.error = undefined;
        this.info = undefined;
    }

    async run(fn, keepBusyOnSuccess) {
        this.isBusy = true;
        this.error = undefined;
        this.info = undefined;
        let ok = false;
        try {
            await fn();
            ok = true;
        } catch (e) {
            this.error = reduceError(e);
        } finally {
            if (!(ok && keepBusyOnSuccess)) {
                this.isBusy = false;
            }
        }
    }

}