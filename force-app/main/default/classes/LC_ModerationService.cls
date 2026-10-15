/**
 * Launched Connect - automatic message screening and flag creation.
 * Rules live in LC_Moderation_Rule__mdt (see Appendix B of the design).
 */
public without sharing class LC_ModerationService {
    public static final String ALLOW = 'Allow';
    public static final String HOLD = 'Hold';
    public static final String FLAG = 'Flag';

    public class Result {
        public String action = ALLOW;
        public String reason;
        public String severity;
        public String ruleName;
        public String messageToSender;
        public List<String> matched = new List<String>();
    }

    @TestVisible
    private static List<LC_Moderation_Rule__mdt> testRules;

    private static List<LC_Moderation_Rule__mdt> cachedRules;

    public static List<LC_Moderation_Rule__mdt> rules() {
        if (testRules != null) {
            return testRules;
        }
        if (cachedRules == null) {
            cachedRules = [
                SELECT DeveloperName, Pattern__c, Reason__c, Severity__c, Action__c, Applies_To__c, Message_To_Sender__c
                FROM LC_Moderation_Rule__mdt
                WHERE Active__c = TRUE
                ORDER BY Sort_Order__c ASC NULLS LAST
            ];
        }
        return cachedRules;
    }

    /** Screens a message. senderType = Prospect | Ambassador | Staff | System */
    public static Result evaluate(String body, String senderType) {
        Result r = new Result();
        if (String.isBlank(body) || senderType == 'Staff' || senderType == 'System') {
            return r;
        }
        for (LC_Moderation_Rule__mdt rule : rules()) {
            if (String.isNotBlank(rule.Applies_To__c) && rule.Applies_To__c != 'All' && rule.Applies_To__c != senderType) {
                continue;
            }
            if (String.isBlank(rule.Pattern__c)) {
                continue;
            }
            Matcher m;
            try {
                m = Pattern.compile('(?i)' + rule.Pattern__c).matcher(body);
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'LC moderation rule has an invalid pattern: ' + rule.DeveloperName);
                continue;
            }
            if (!m.find()) {
                continue;
            }
            if (rule.Reason__c == 'Contact details' && isOnlyAllowedLinks(body, rule)) {
                continue;
            }
            String act = rule.Action__c == 'Hold' ? HOLD : FLAG;
            if (act == HOLD) {
                r.action = HOLD;
                if (r.messageToSender == null) {
                    r.messageToSender = rule.Message_To_Sender__c;
                }
            } else if (r.action == ALLOW) {
                r.action = FLAG;
            }
            r.matched.add(rule.DeveloperName);
            if (r.ruleName == null || rank(rule.Severity__c) > rank(r.severity)) {
                r.ruleName = rule.DeveloperName;
                r.reason = rule.Reason__c;
                r.severity = rule.Severity__c;
            }
        }
        if (r.action == HOLD && String.isBlank(r.messageToSender)) {
            r.messageToSender = 'Your message is being checked by the university before it is delivered. Please keep chats on Launched Connect.';
        }
        return r;
    }

    /** Creates a Connect Flag owned by the moderation queue. Returns the new Id. */
    public static Id createFlag(
        Id conversationId,
        Id messageId,
        String source,
        String reason,
        String severity,
        String ruleName,
        String details,
        Id reportedBy
    ) {
        Connect_Conversation__c conv = [
            SELECT Id, Prospect_Age_Band__c, Status__c
            FROM Connect_Conversation__c
            WHERE Id = :conversationId
            LIMIT 1
        ];
        Boolean under18 = conv.Prospect_Age_Band__c == 'Under 16' || conv.Prospect_Age_Band__c == '16-17';
        String finalSeverity = String.isBlank(severity) ? 'Medium' : severity;
        if (under18) {
            finalSeverity = bump(finalSeverity);
        }
        Connect_Flag__c flag = new Connect_Flag__c(
            Conversation__c = conversationId,
            Message__c = messageId,
            Source__c = source,
            Reason__c = String.isBlank(reason) ? 'Other' : reason,
            Severity__c = finalSeverity,
            Status__c = 'New',
            Rule_Name__c = ruleName == null ? null : ruleName.left(80),
            Details__c = details == null ? null : details.left(2000),
            Reported_By__c = reportedBy,
            Prospect_Under_18__c = under18
        );
        Id queueId = LC_Settings.moderationQueueId();
        flag.OwnerId = queueId != null ? queueId : LC_Settings.recordOwnerId();
        insert flag;

        Connect_Conversation__c upd = new Connect_Conversation__c(Id = conversationId);
        upd.Open_Flag_Count__c = [
            SELECT COUNT()
            FROM Connect_Flag__c
            WHERE Conversation__c = :conversationId AND Status__c != 'Resolved'
        ];
        if (finalSeverity == 'High' && conv.Status__c != 'Closed') {
            upd.Status__c = 'Under Review';
        }
        update upd;
        return flag.Id;
    }

    // ---------------------------------------------------------------- helpers

    private static Boolean isOnlyAllowedLinks(String body, LC_Moderation_Rule__mdt rule) {
        if (rule.DeveloperName == null || !rule.DeveloperName.startsWith('Web_Link')) {
            return false;
        }
        Set<String> allowed = LC_Settings.allowedLinkDomains();
        if (allowed.isEmpty()) {
            return false;
        }
        Matcher m = Pattern.compile('(?i)(?:https?://|www\\.)([a-z0-9.\\-]+)').matcher(body);
        Boolean foundLink = false;
        while (m.find()) {
            foundLink = true;
            String host = m.group(1).toLowerCase();
            if (host.startsWith('www.')) {
                host = host.substring(4);
            }
            Boolean ok = false;
            for (String d : allowed) {
                if (host == d || host.endsWith('.' + d)) {
                    ok = true;
                    break;
                }
            }
            if (!ok) {
                return false;
            }
        }
        return foundLink;
    }

    @TestVisible
    private static Integer rank(String severity) {
        if (severity == 'High') {
            return 3;
        }
        if (severity == 'Medium') {
            return 2;
        }
        if (severity == 'Low') {
            return 1;
        }
        return 0;
    }

    private static String bump(String severity) {
        return severity == 'Low' ? 'Medium' : 'High';
    }
}