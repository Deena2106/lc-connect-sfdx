import { LightningElement, api } from 'lwc';

/**
 * Launched Connect - "Report a concern" dialog (child component).
 * Fires "submit" with detail { reason, details } or "cancel".
 */
export default class LcReportConcern extends LightningElement {
    @api open = false;
    reason = '';
    details = '';

    reasonOptions = [
        { label: 'They asked for or shared personal contact details', value: 'Contact details' },
        { label: 'Rude or offensive language', value: 'Offensive language' },
        { label: 'Behaviour that made me feel uncomfortable or unsafe', value: 'Inappropriate behaviour' },
        { label: 'Spam, selling or asking for money', value: 'Spam or fraud' },
        { label: 'Something else', value: 'Other' }
    ];

    get submitDisabled() {
        return !this.reason;
    }

    handleReason(event) {
        this.reason = event.detail.value;
    }

    handleDetails(event) {
        this.details = event.detail.value;
    }

    handleSubmit() {
        this.dispatchEvent(new CustomEvent('submit', { detail: { reason: this.reason, details: this.details } }));
        this.reason = '';
        this.details = '';
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('cancel'));
    }

    handleKey(event) {
        if (event.key === 'Escape') {
            this.handleCancel();
        }
    }
}