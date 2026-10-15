import { LightningElement, wire } from 'lwc';
import isGuest from '@salesforce/user/isGuest';
import userId from '@salesforce/user/Id';
import basePath from '@salesforce/community/basePath';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import NAME_FIELD from '@salesforce/schema/User.Name';

export default class CustomHeader extends LightningElement {
    isGuest = isGuest;
    userName = 'User'; // Fallback

    get logoutUrl() {
        return `${basePath}/secur/logout.jsp`;
    }

    @wire(getRecord, { recordId: userId, fields: [NAME_FIELD] })
    wiredUser({ error, data }) {
        if (data) {
            this.userName = getFieldValue(data, NAME_FIELD);
        }
    }
}