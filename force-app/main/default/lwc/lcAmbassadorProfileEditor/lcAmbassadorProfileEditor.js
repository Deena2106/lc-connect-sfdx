import { LightningElement } from 'lwc';
import getMyProfile from '@salesforce/apex/LC_AmbassadorController.getMyProfile';
import saveMyProfile from '@salesforce/apex/LC_AmbassadorController.saveMyProfile';
// import updatePhotoStatus from '@salesforce/apex/LC_AmbassadorController.updatePhotoStatus';
import updatePhoto from '@salesforce/apex/LC_AmbassadorController.updatePhoto';
import { reduceError, siteUrl, ROUTES } from 'c/lcUtils';

const STATUS_HELP = {
    Draft: 'Your profile is not public yet. Save it to send it for review.',
    'In Review': 'The ambassador team is checking your profile. It will go live once approved.',
    Published: 'Your profile is live on the website.',
    Paused: 'Your profile is hidden for now. Contact the ambassador team to restart.',
    Retired: 'Your ambassador role has ended. Thank you!'
};

/**
 * Launched Connect - ambassador edits their own public profile (My Profile page, Ambassadors audience).
 */
export default class LcAmbassadorProfileEditor extends LightningElement {
    profile;
    form = {};
    isLoading = true;
    isSaving = false;
    error;
    saved;
    acceptedFormats = ['.jpg', '.jpeg', '.png'];

    get homeUrl() {
        return siteUrl(ROUTES.home);
        // return `${window.location.origin}${siteUrl(ROUTES.home)}`
    }
    get statusHelp() {
        return STATUS_HELP[this.profile.status] || '';
    }
    get statusClass() {
        return this.profile.status === 'Published' ? 'ed__status ed__status_live' : 'ed__status';
    }

    async connectedCallback() {
        try {
            const p = await getMyProfile();
            this.profile = p;
            this.form = {
                displayName: p.displayName || '',
                headline: p.headline || '',
                bio: p.bio || '',
                homeCountry: p.homeCountry || '',
                homeCity: p.homeCity || '',
                livedInHalls: p.livedInHalls === true,
                interests: p.interests || [],
                languages: p.languages || []
            };
        } catch (e) {
            const message = reduceError(e);
            if (message.indexOf('for student ambassadors') >= 0) {
                window.location.assign(siteUrl(ROUTES.messages));
                return;
            }
            this.error = message;
        } finally {
            this.isLoading = false;
        }
    }

    handleChange(event) {
        const { name, type } = event.target;
        const value = type === 'checkbox' ? event.target.checked : event.detail.value;
        this.form = { ...this.form, [name]: value };
        this.saved = undefined;
    }

    async handleSave(event) {
        event.preventDefault();
        const inputs = [...this.template.querySelectorAll('lightning-input, lightning-textarea')];
        if (!inputs.reduce((ok, i) => i.reportValidity() && ok, true)) {
            return;
        }
        if ((this.form.interests || []).length > 5) {
            this.error = 'Please choose up to five interests.';
            return;
        }
        this.isSaving = true;
        this.error = undefined;
        try {
            const status = await saveMyProfile({ input: this.form });
            this.profile = { ...this.profile, status };
            this.saved = status === 'In Review' ? 'Saved. Your changes have been sent for review.' : 'Saved.';
        } catch (e) {
            this.error = reduceError(e);
        } finally {
            this.isSaving = false;
        }
    }
    async handleUpload(event) {
        try {
            const files = event.detail.files;
            if (!files || files.length === 0) {
                return;
            }
            const contentDocumentId = files[0].documentId;
            const result = await updatePhoto({
                contentDocumentId: contentDocumentId
            });
            this.profile = {
                ...this.profile,
                status: result.status,
                photoUrl: result.photoUrl
            };
            this.saved = 'Photo uploaded. Your changes have been sent for review.';
            this.error = undefined;

        } catch (e) {
            this.error = reduceError(e);
            this.saved = undefined;
        }
    }
}