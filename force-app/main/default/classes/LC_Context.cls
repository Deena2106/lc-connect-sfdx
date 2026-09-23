/**
 * Launched Connect - who is the current viewer?
 * Runs without sharing so it can read the viewer's own User, Contact and
 * ambassador record. It only ever returns data about the running user.
 */
public without sharing class LC_Context {
    public class Viewer {
        public Id userId;
        public Id contactId;
        public Id accountId;
        public String firstName;
        public Boolean isGuest = false;
        public Boolean isAmbassador = false;
        public Id ambassadorId;
        public String ambassadorName;
    }

    private static Viewer cached;

    public static Viewer current() {
        if (cached != null) {
            return cached;
        }
        Viewer v = new Viewer();
        v.userId = UserInfo.getUserId();
        v.isGuest = UserInfo.getUserType() == 'Guest';
        if (!v.isGuest) {
            User u = [SELECT ContactId, AccountId, FirstName FROM User WHERE Id = :v.userId LIMIT 1];
            v.contactId = u.ContactId;
            v.accountId = u.AccountId;
            v.firstName = u.FirstName;
            if (v.contactId != null) {
                List<Connect_Ambassador__c> amb = [
                    SELECT Id, Display_Name__c
                    FROM Connect_Ambassador__c
                    WHERE Contact__c = :v.contactId AND Status__c != 'Retired'
                    ORDER BY CreatedDate DESC
                    LIMIT 1
                ];
                if (!amb.isEmpty()) {
                    v.isAmbassador = true;
                    v.ambassadorId = amb[0].Id;
                    v.ambassadorName = amb[0].Display_Name__c;
                }
            }
        }
        cached = v;
        return v;
    }

    /** Throws a friendly error unless the viewer is a logged-in Experience Cloud user. */
    public static Viewer requireExternalUser() {
        Viewer v = current();
        if (v.isGuest || v.contactId == null) {
            throw error('Please log in to continue.');
        }
        return v;
    }

    /** AuraHandledException with a readable message (also visible in tests). */
    public static AuraHandledException error(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }

    @TestVisible
    private static void reset() {
        cached = null;
    }
}
