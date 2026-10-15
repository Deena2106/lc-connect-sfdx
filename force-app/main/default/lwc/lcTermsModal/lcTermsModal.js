import { LightningElement } from 'lwc';
import getGuidelinesStatus from '@salesforce/apex/TermsModalController.getGuidelinesStatus';
import acceptGuidelines from '@salesforce/apex/TermsModalController.acceptGuidelines';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class LcTermsModal extends LightningElement {
    showModal = false;
    isChecked = false;
    isSaving = false;
    errorMessage = '';
    currentVersion = '';
    verificationFailed = false;

    connectedCallback() {
        this.checkGuidelines();
    }

    async checkGuidelines() {
        try {
            const result = await getGuidelinesStatus();
            this.currentVersion = result.currentVersion;
            this.showModal = !result.accepted;
            this.verificationFailed = false;
            this.errorMessage = '';
        } catch (error) {
            // Fail closed: keep the modal visible if the server cannot verify acceptance.
            this.showModal = true;
            this.verificationFailed = true;
            this.errorMessage =
                error?.body?.message ||
                'We could not verify your guidelines acceptance. Please refresh or contact support.';
        }
    }

    handleCheckboxChange(event) {
        this.isChecked = event.target.checked;
        if (this.isChecked) {
            this.errorMessage = '';
        }
    }

    get isAcceptDisabled() {
        return !this.isChecked || this.isSaving || this.verificationFailed || !this.currentVersion;
    }

    async handleAccept() {
        if (this.isAcceptDisabled) {
            return;
        }

        this.isSaving = true;
        this.errorMessage = '';

        try {
            await acceptGuidelines({ acceptedVersion: this.currentVersion });
            this.showModal = false;

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Guidelines accepted',
                    message: 'Your acceptance has been saved. You can now use Launched Connect chat.',
                    variant: 'success'
                })
            );

            this.dispatchEvent(new CustomEvent('guidelinesaccepted', {
                bubbles: true,
                composed: true
            }));
        } catch (error) {
            this.errorMessage =
                error?.body?.message ||
                'We could not save your acceptance. Please try again.';
        } finally {
            this.isSaving = false;
        }
    }
}
