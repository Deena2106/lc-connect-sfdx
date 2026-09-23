/**
 * Launched Connect - @AuraEnabled facade used by the chat LWCs.
 * All security checks live in the service classes.
 */
public with sharing class LC_ChatController {
    @AuraEnabled
    public static List<LC_ConversationService.ConversationSummary> listMyConversations() {
        return LC_ConversationService.listMine();
    }

    @AuraEnabled
    public static LC_ConversationService.Thread getThread(Id conversationId, Datetime since) {
        return LC_ConversationService.getThread(conversationId, since);
    }

    @AuraEnabled
    public static Id startConversation(String ambassador, String origin) {
        return LC_ConversationService.startWithAmbassador(ambassador, origin);
    }

    @AuraEnabled
    public static LC_MessageService.SendResult sendMessage(Id conversationId, String body, String clientMessageId) {
        return LC_MessageService.send(conversationId, body, clientMessageId, 'Web');
    }

    @AuraEnabled
    public static void closeConversation(Id conversationId) {
        LC_ConversationService.close(conversationId);
    }

    @AuraEnabled
    public static void reportConcern(Id conversationId, Id messageId, String reason, String details) {
        LC_Context.Viewer v = LC_Context.requireExternalUser();
        LC_ConversationService.loadForParticipant(conversationId, v);
        Set<String> reasons = new Set<String>{ 'Contact details', 'Offensive language', 'Safeguarding keyword', 'Spam or fraud', 'Inappropriate behaviour', 'Other' };
        String r = reasons.contains(reason) ? reason : 'Other';
        String severity = (r == 'Inappropriate behaviour' || r == 'Safeguarding keyword') ? 'High' : 'Medium';
        LC_ModerationService.createFlag(conversationId, messageId, 'User report', r, severity, null, details, v.userId);
    }

    @AuraEnabled
    public static Id askAdmissions(String subCategory, String question) {
        return LC_AdmissionsService.askAdmissions(subCategory, question);
    }

    @AuraEnabled
    public static Id referToAdmissions(Id conversationId, String subCategory, String note) {
        return LC_AdmissionsService.referFromConversation(conversationId, subCategory, note);
    }
}
