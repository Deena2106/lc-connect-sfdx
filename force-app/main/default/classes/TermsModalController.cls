// public with sharing class TermsModalController {

//     @AuraEnabled(cacheable=true)
//     public static Account getUserContactDetails() {
//         User currentUser = [SELECT Id, ContactId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
//         if (currentUser.ContactId == null) {
//             return null;
//         }
//         List<Account> accList = [
//             SELECT Id, Guidelines_Accepted__c, Terms_Accepted_Version__c, Terms_Accepted_Date__c 
//             FROM Account 
//             WHERE PersonContactId = :currentUser.ContactId 
//             LIMIT 1
//         ];
//         return accList.isEmpty() ? null : accList[0];
//     }

//     @AuraEnabled
//     public static void acceptTerms(String accountId, String version) {
//         if (String.isNotBlank(accountId)) {
//             Account acc = new Account(
//                 Id  = accountId,
//                 Guidelines_Accepted__c = true,
//                 Terms_Accepted_Version__c = version,
//                 Terms_Accepted_Date__c = System.now()
//             );
//             update acc;
//         }
//     }
// }

public with sharing class TermsModalController {

    // Increment this value whenever the guidelines change.
    private static final String CURRENT_VERSION = '1.0';

    public class GuidelinesStatus {
        @AuraEnabled public Boolean accepted { get; set; }
        @AuraEnabled public String currentVersion { get; set; }
    }

    @AuraEnabled
    public static GuidelinesStatus getGuidelinesStatus() {
        GuidelinesStatus result = new GuidelinesStatus();
        result.currentVersion = CURRENT_VERSION;
        result.accepted = false;

        Id contactId = getCurrentUserContactId();

        if (contactId == null) {
            throw new AuraHandledException(
                'Your Experience Cloud user is not linked to a Contact. Please contact support.'
            );
        }

        List<Account> accounts = [
            SELECT Id,
                   Guidelines_Accepted__c,
                   Terms_Accepted_Version__c,
                   Terms_Accepted_Date__c
            FROM Account
            WHERE PersonContactId = :contactId
            LIMIT 1
        ];

        if (!accounts.isEmpty()) {
            Account personAccount = accounts[0];

            result.accepted =
                personAccount.Guidelines_Accepted__c == true &&
                personAccount.Terms_Accepted_Date__c != null &&
                personAccount.Terms_Accepted_Version__c == CURRENT_VERSION;
        }

        return result;
    }

    @AuraEnabled
    public static void acceptGuidelines(String acceptedVersion) {

        if (String.isBlank(acceptedVersion) ||
            acceptedVersion != CURRENT_VERSION) {
            throw new AuraHandledException(
                'The guidelines have changed. Please reload the page and accept the latest version.'
            );
        }

        Id contactId = getCurrentUserContactId();

        if (contactId == null) {
            throw new AuraHandledException(
                'Your Experience Cloud user is not linked to a Contact. Please contact support.'
            );
        }

        List<Account> accounts = [
            SELECT Id,
                   Guidelines_Accepted__c,
                   Terms_Accepted_Version__c,
                   Terms_Accepted_Date__c
            FROM Account
            WHERE PersonContactId = :contactId
            LIMIT 1
            FOR UPDATE
        ];

        if (accounts.isEmpty()) {
            throw new AuraHandledException(
                'Your Person Account was not found. Please contact support.'
            );
        }

        Account personAccount = accounts[0];

        personAccount.Guidelines_Accepted__c = true;
        personAccount.Terms_Accepted_Date__c = System.now();
        personAccount.Terms_Accepted_Version__c = CURRENT_VERSION;

        update personAccount;
    }

    /*
     * Call this method from every server-side chat operation
     * that must be restricted until the current guidelines are accepted.
     */
    @AuraEnabled
    public static void assertCurrentGuidelinesAccepted() {

        GuidelinesStatus status = getGuidelinesStatus();

        if (status.accepted != true) {
            throw new AuraHandledException(
                'Please accept the current Launched Connect guidelines before chatting.'
            );
        }
    }

    private static Id getCurrentUserContactId() {
        User currentUser = [
            SELECT ContactId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        return currentUser.ContactId;
    }
}
