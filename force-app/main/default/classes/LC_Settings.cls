/**
 * Launched Connect - reads the LC_Setting__mdt "Default" record, with safe defaults.
 * Without sharing so guest and community users can resolve the owner user and queues.
 */
public without sharing class LC_Settings {
    private static LC_Setting__mdt cached;
    private static Map<String, Id> queueCache = new Map<String, Id>();
    private static Id ownerCache;

    public static LC_Setting__mdt get() {
        if (cached == null) {
            cached = LC_Setting__mdt.getInstance('Default');
            if (cached == null) {
                cached = new LC_Setting__mdt(
                    Poll_Interval_Seconds__c = 5,
                    Max_Messages_Per_Minute__c = 10,
                    Max_New_Conversations_Per_Day__c = 5,
                    Retention_Months__c = 24,
                    Guidelines_Version__c = '1.0',
                    Minimum_Age__c = 16,
                    Moderation_Queue__c = 'Connect_Moderation',
                    Admissions_Queue__c = 'UG_Admissions',
                    Allowed_Link_Domains__c = ''
                );
            }
        }
        return cached;
    }

    public static Integer pollSeconds() {
        return toInt(get().Poll_Interval_Seconds__c, 5);
    }
    public static Integer maxMessagesPerMinute() {
        return toInt(get().Max_Messages_Per_Minute__c, 10);
    }
    public static Integer maxConversationsPerDay() {
        return toInt(get().Max_New_Conversations_Per_Day__c, 5);
    }
    public static Integer retentionMonths() {
        return toInt(get().Retention_Months__c, 24);
    }
    public static Integer minimumAge() {
        return toInt(get().Minimum_Age__c, 16);
    }
    public static String guidelinesVersion() {
        return String.isBlank(get().Guidelines_Version__c) ? '1.0' : get().Guidelines_Version__c;
    }

    public static Set<String> allowedLinkDomains() {
        Set<String> out = new Set<String>();
        String raw = get().Allowed_Link_Domains__c;
        if (String.isNotBlank(raw)) {
            for (String d : raw.split(',')) {
                if (String.isNotBlank(d)) {
                    out.add(d.trim().toLowerCase());
                }
            }
        }
        return out;
    }

    /** Internal user who owns conversations. Falls back to the running user in tests / internal context. */
    public static Id recordOwnerId() {
        if (ownerCache != null) {
            return ownerCache;
        }
        String username = get().Record_Owner_Username__c;
        if (String.isNotBlank(username)) {
            List<User> users = [SELECT Id FROM User WHERE Username = :username AND IsActive = TRUE LIMIT 1];
            if (!users.isEmpty()) {
                ownerCache = users[0].Id;
                return ownerCache;
            }
        }
        if (UserInfo.getUserType() == 'Standard') {
            ownerCache = UserInfo.getUserId();
            return ownerCache;
        }
        throw LC_Context.error('Launched Connect is not fully configured (record owner). Please contact the university.');
    }

    public static Id queueId(String developerName) {
        if (String.isBlank(developerName)) {
            return null;
        }
        if (!queueCache.containsKey(developerName)) {
            List<Group> g = [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = :developerName LIMIT 1];
            queueCache.put(developerName, g.isEmpty() ? null : g[0].Id);
        }
        return queueCache.get(developerName);
    }

    public static Id moderationQueueId() {
        return queueId(get().Moderation_Queue__c);
    }
    public static Id admissionsQueueId() {
        return queueId(get().Admissions_Queue__c);
    }

    public static Id caseRecordTypeId(String developerName) {
        Schema.RecordTypeInfo info = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get(developerName);
        return info == null ? null : info.getRecordTypeId();
    }

    private static Integer toInt(Decimal d, Integer fallback) {
        return d == null ? fallback : d.intValue();
    }

    @TestVisible
    private static void setForTest(LC_Setting__mdt setting) {
        cached = setting;
        ownerCache = null;
    }
}
