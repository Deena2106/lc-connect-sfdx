import { LightningElement } from 'lwc';
const GUIDELINES_VERSION = '1.0';
export default class LcStudentTeamsModel extends LightningElement {
    isAccepted = false;
    errorMessage = '';
    get currentVersion() {
        return GUIDELINES_VERSION;
    }
    get acceptDisabled() {
        return !this.isAccepted;
    }
    handleCheckboxChange(event) {
        this.isAccepted = event.target.checked;

        if (this.isAccepted) {
            this.errorMessage = '';
        }
    }
    handleAccept() {
        if (!this.isAccepted) {
            this.errorMessage =
                'Please accept the Student Guidelines to continue.';
            return;
        }
        this.errorMessage = '';
        this.dispatchEvent(
            new CustomEvent('studentguidelinesaccepted', {
                detail: {
                    accepted: true,
                    version: GUIDELINES_VERSION
                }
            })
        );
    }
}