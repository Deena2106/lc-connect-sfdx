import { LightningElement, api } from 'lwc';
import isGuest from '@salesforce/user/isGuest';
import searchAmbassadors from '@salesforce/apex/LC_DirectoryController.searchAmbassadors';
import getFilterOptions from '@salesforce/apex/LC_DirectoryController.getFilterOptions';
import { goToChat, queryParam, reduceError, rememberUtm } from 'c/lcUtils';

const ANY = { label: 'Any', value: '' };

/**
 * Launched Connect - public ambassador directory (Home page).
 */
export default class LcAmbassadorDirectory extends LightningElement {
    @api heading = 'Chat to a current student';
    @api intro =
        "Choosing a university is a big decision. Talk to someone who knows what it's really like. Find an ambassador studying the subject you're interested in, or from the country you're from.";
    @api disclaimer = 'Ambassadors are current students appointed and trained by the university.';
    @api pageSize = 12;

    searchTerm = '';
    subject = '';
    studyLevel = '';
    country = '';
    language = '';

    ambassadors = [];
    total = 0;
    onlineCount = 0;
    hasMore = false;
    pageNumber = 1;
    isLoading = false;
    error;

    subjectOptions = [ANY];
    levelOptions = [ANY];
    countryOptions = [ANY];
    languageOptions = [ANY];

    connectedCallback() {
        rememberUtm();
        this.subject = queryParam('subject') || '';
        this.studyLevel = queryParam('level') || '';
        this.country = queryParam('country') || '';
        this.searchTerm = queryParam('q') || '';
        this.loadOptions();
        this.search(true);
    }

    get isEmpty() {
        return !this.isLoading && !this.error && this.ambassadors.length === 0;
    }

    get hasFilters() {
        return Boolean(this.searchTerm || this.subject || this.studyLevel || this.country || this.language);
    }

    async loadOptions() {
        try {
            const opts = await getFilterOptions();
            this.subjectOptions = [ANY, ...opts.subjects];
            this.levelOptions = [ANY, ...opts.studyLevels];
            this.countryOptions = [ANY, ...opts.countries];
            this.languageOptions = [ANY, ...opts.languages];
        } catch (e) {
            this.error = reduceError(e);
        }
    }

    async search(reset) {
        if (reset) {
            this.pageNumber = 1;
        }
        this.isLoading = true;
        this.error = undefined;
        try {
            const result = await searchAmbassadors({
                searchTerm: this.searchTerm,
                subject: this.subject,
                studyLevel: this.studyLevel,
                country: this.country,
                language: this.language,
                pageSize: Number(this.pageSize) || 12,
                pageNumber: this.pageNumber
            });
            this.ambassadors = reset ? result.ambassadors : [...this.ambassadors, ...result.ambassadors];
            this.total = result.total;
            this.onlineCount = result.onlineCount;
            this.hasMore = result.hasMore;
        } catch (e) {
            this.error = reduceError(e);
        } finally {
            this.isLoading = false;
        }
    }

    handleTermChange(event) {
        this.searchTerm = event.target.value;
        if (!this.searchTerm) {
            this.search(true);
        }
    }

    handleSearch(event) {
        event.preventDefault();
        this.search(true);
    }

    handleFilter(event) {
        this[event.target.name] = event.detail.value;
        this.search(true);
    }

    clearFilters() {
        this.searchTerm = '';
        this.subject = '';
        this.studyLevel = '';
        this.country = '';
        this.language = '';
        this.search(true);
    }

    loadMore() {
        this.pageNumber += 1;
        this.search(false);
    }

    handleAsk(event) {
        goToChat(event.detail.slug, 'Directory', isGuest);
    }
}
