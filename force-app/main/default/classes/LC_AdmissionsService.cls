/**
 * Launched Connect - hand-off to the admissions team.
 * Creates an Educational Info Request, a Connect Admissions Question Case and a
 * staff conversation, so the reply appears in the prospect's Launched Connect inbox.
 */
public without sharing class LC_AdmissionsService {
    public static final Set<String> SUB_CATEGORIES = new Set<String>{
        'Application Process', 'Housing', 'Program Info', 'Scholarship', 'Tuition Fee'
    };

    /** Called by a prospect from the chat side panel. Returns the new staff conversation Id. */
    public static Id askAdmissions(String subCategory, String question) {
        LC_Context.Viewer v = LC_Context.requireExternalUser();
        if (v.isAmbassador) {
            throw LC_Context.error('Ambassadors should use Refer to admissions team inside a chat.');
        }
        if (String.isBlank(question) || question.trim().length() < 5) {
            throw LC_Context.error('Please type your question.');
        }
        Connect_Conversation__c conv = createRequest(
            v.contactId, v.accountId, subCategory, question.trim(), 'Question from ' + (v.firstName == null ? 'prospect' : v.firstName)
        );
        Connect_Message__c m = new Connect_Message__c(
            Conversation__c = conv.Id,
            Sender_Type__c = 'Prospect',
            Sender_User__c = v.userId,
            Sender_Display_Name__c = v.firstName,
            Body__c = question.trim().left(LC_MessageService.MAX_LENGTH),
            Visibility__c = 'Visible',
            Moderation_Result__c = 'Allowed',
            Channel__c = 'Web'
        );
        insert m;
        conv = [SELECT Id, Status__c, Started_At__c, First_Response_At__c, Prospect__r.AccountId, Ambassador__c FROM Connect_Conversation__c WHERE Id = :conv.Id];
        LC_MessageService.afterVisibleMessage(conv, m, 'Prospect');
        return conv.Id;
    }

    /** Called by an ambassador from inside a conversation. */
    public static Id referFromConversation(Id conversationId, String subCategory, String note) {
        LC_Context.Viewer v = LC_Context.requireExternalUser();
        Connect_Conversation__c c = LC_ConversationService.loadForParticipant(conversationId, v);
        if (LC_ConversationService.roleFor(c, v) != LC_ConversationService.ROLE_AMBASSADOR) {
            throw LC_Context.error('Only the ambassador can refer this chat.');
        }
        String text = String.isBlank(note) ? 'Referred by ambassador ' + v.ambassadorName : note.trim();
        Connect_Conversation__c staffConv = createRequest(
            c.Prospect__c, c.Prospect__r.AccountId, subCategory,
            'Referred by ambassador ' + v.ambassadorName + ' from ' + c.Name + ':\n' + text,
            'Referral from ' + v.ambassadorName
        );
        LC_ConversationService.insertSystemMessage(
            staffConv.Id,
            v.ambassadorName + ' asked the admissions team to help with your question. They will reply here.'
        );
        LC_ConversationService.insertSystemMessage(
            c.Id,
            v.ambassadorName + ' has passed your question to the admissions team. Look for their reply in My chats.'
        );
        update new Connect_Conversation__c(Id = c.Id, Info_Request__c = staffConv.Info_Request__c, Case__c = staffConv.Case__c);
        return staffConv.Id;
    }

    // ---------------------------------------------------------------- helpers

    /** Returns the active picklist value matching the label or API name, or null if the org has no match. */
    @TestVisible
    private static String picklistValue(Schema.SObjectField field, String wanted) {
        for (Schema.PicklistEntry e : field.getDescribe().getPicklistValues()) {
            if (e.isActive() && (e.getValue().equalsIgnoreCase(wanted) || e.getLabel().equalsIgnoreCase(wanted))) {
                return e.getValue();
            }
        }
        return null;
    }

    private static Connect_Conversation__c createRequest(Id contactId, Id accountId, String subCategory, String description, String subjectPrefix) {
        String sub = SUB_CATEGORIES.contains(subCategory) ? subCategory : 'Application Process';

        Case cs = new Case(
            Subject = ('Launched Connect: ' + subjectPrefix + ' (' + sub + ')').left(255),
            Description = description.left(32000),
            ContactId = contactId,
            AccountId = accountId,
            Origin = 'Web'
        );
        Id rt = LC_Settings.caseRecordTypeId('Connect_Admissions_Question');
        if (rt != null) {
            cs.RecordTypeId = rt;
        }
        Id queueId = LC_Settings.admissionsQueueId();
        cs.OwnerId = queueId != null ? queueId : LC_Settings.recordOwnerId();
        insert cs;

        EducationalInfoRequest eir = new EducationalInfoRequest(
            Name = ('Connect: ' + sub).left(80),
            Category = picklistValue(EducationalInfoRequest.Category, 'Admission'),
            SubCategory = picklistValue(EducationalInfoRequest.SubCategory, sub),
            RequesterId = accountId,
            CaseId = cs.Id
        );
        insert eir;

        Connect_Conversation__c conv = LC_ConversationService.newConversation(contactId, 'Staff', 'Staff');
        conv.Status__c = 'Awaiting Reply';
        conv.Case__c = cs.Id;
        conv.Info_Request__c = eir.Id;
        insert conv;

        update new Case(Id = cs.Id, Connect_Conversation__c = conv.Id);
        return conv;
    }
}
