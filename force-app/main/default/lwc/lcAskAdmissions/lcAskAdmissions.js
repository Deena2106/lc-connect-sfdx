import { LightningElement, api } from 'lwc';

/**
 * Launched Connect - question for the admissions team (child component).
 * mode = 'ask' (prospect) or 'refer' (ambassador). Fires "submit" { subCategory, text } or "cancel".
 */
export default class LcAskAdmissions extends LightningElement {
    @api open = false;
    @api mode = 'ask';
    subCategory = 'Application Process';
    text = '';

    // Values match the Educational Info Request SubCategory picklist.
    topicOptions = [
        { label: 'Applying and entry requirements', value: 'Application Process' },
        { label: 'Course information', value: 'Program Info' },
        { label: 'Fees', value: 'Tuition Fee' },
        { label: 'Scholarships and funding', value: 'Scholarship' },
        { label: 'Accommodation', value: 'Housing' }
    ];

    get isAsk() {
        return this.mode !== 'refer';
    }
    get title() {
        return this.isAsk ? 'Ask the admissions team' : 'Refer to the admissions team';
    }
    get intro() {
        return this.isAsk
            ? 'For questions about applications, offers, fees or visas. The team will reply in a new chat in My chats.'
            : 'The admissions team will pick this up and reply to the student in a new chat. Add a short note to explain what they need.';
    }
    get textLabel() {
        return this.isAsk ? 'Your question' : 'Note for the admissions team';
    }
    get submitLabel() {
        return this.isAsk ? 'Send question' : 'Refer';
    }
    get submitDisabled() {
        return this.isAsk && this.text.trim().length < 5;
    }

    handleTopic(event) {
        this.subCategory = event.detail.value;
    }
    handleText(event) {
        this.text = event.detail.value || '';
    }
    handleSubmit() {
        this.dispatchEvent(new CustomEvent('submit', { detail: { subCategory: this.subCategory, text: this.text } }));
        this.text = '';
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