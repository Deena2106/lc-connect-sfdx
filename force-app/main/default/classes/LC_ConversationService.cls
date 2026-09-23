/**
 * Launched Connect - conversations and messages.
 *
 * Security model: every public method first checks that the running user is a
 * participant (their Contact is the Prospect or the Ambassador Contact). Only
 * then does it read or write, in system mode, and it only returns the fields in
 * the DTOs below. Ambassadors never receive a prospect's surname, email or DOB.
 */
public without sharing class LC_ConversationService {
    public static final String ROLE_PROSPECT = 'Prospect';
    public static final String ROLE_AMBASSADOR = 'Ambassador';
    private static final Set<String> LOCKED_STATUSES = new Set<String>{ 'Paused', 'Under Review', 'Closed' };

    // ------------------------------------------------------------------ DTOs

    public class ConversationSummary {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String channelType;
        @AuraEnabled public String status;
        @AuraEnabled public String counterpartName;
        @AuraEnabled public String counterpartSubtitle;
        @AuraEnabled public String counterpartPhotoUrl;
        @AuraEnabled public String lastMessagePreview;
        @AuraEnabled public String lastMessageBy;
        @AuraEnabled public Datetime lastMessageAt;
        @AuraEnabled public Boolean unread;
        @AuraEnabled public Decimal waitingHours;
    }

    public class MessageItem {
        @AuraEnabled public Id id;
        @AuraEnabled public String body;
        @AuraEnabled public String senderType;
        @AuraEnabled public String senderName;
        @AuraEnabled public Boolean mine;
        @AuraEnabled public String visibility;
        @AuraEnabled public String notice;
        @AuraEnabled public Datetime sentAt;
        @AuraEnabled public String clientMessageId;
    }

    public class Thread {
        @AuraEnabled public ConversationSummary conversation;
        @AuraEnabled public String role;
        @AuraEnabled public Boolean canSend;
        @AuraEnabled public String lockedReason;
        @AuraEnabled public List<MessageItem> messages = new List<MessageItem>();
        @AuraEnabled public Integer pollSeconds;
        @AuraEnabled public Datetime serverTime;
        @AuraEnabled public String prospectCountry;
        @AuraEnabled public String prospectInterest;
    }

    // ----------------------------------------------------------- inbox list

    public static List<ConversationSummary> listMine() {
        LC_Context.Viewer v = LC_Context.requireExternalUser();
        List<Connect_Conversation__c> rows = [
            SELECT
                Id, Name, Channel_Type__c, Status__c, Prospect__c, Prospect__r.FirstName, Prospect__r.MailingCountry,
                Ambassador_Contact__c, Ambassador__r.Display_Name__c, Ambassador__r.Photo_Url__c,
                Ambassador__r.Learning_Program__r.Name, Last_Message_Preview__c, Last_Message_By__c,
                Last_Message_At__c, Prospect_Unread__c, Ambassador_Unread__c, Waiting_Hours__c, Started_At__c
            FROM Connect_Conversation__c
            WHERE Prospect__c = :v.contactId OR Ambassador_Contact__c = :v.contactId
            ORDER BY Last_Message_At__c DESC NULLS LAST, Started_At__c DESC
            LIMIT 200
        ];
        List<ConversationSummary> out = new List<ConversationSummary>();
        for (Connect_Conversation__c c : rows) {
            out.add(toSummary(c, roleFor(c, v)));
        }
        return out;
    }

    // ---------------------------------------------------------------- thread

    public static Thread getThread(Id conversationId, Datetime since) {
        LC_Context.Viewer v = LC_Context.requireExternalUser();
        Connect_Conversation__c c = loadForParticipant(conversationId, v);
        String role = roleFor(c, v);

        Thread t = new Thread();
        t.conversation = toSummary(c, role);
        t.role = role;
        t.canSend = !LOCKED_STATUSES.contains(c.Status__c);
        t.lockedReason = lockedReason(c.Status__c);
        t.pollSeconds = LC_Settings.pollSeconds();
        t.serverTime = Datetime.now();
        if (role == ROLE_AMBASSADOR) {
            t.prospectCountry = c.Prospect__r.MailingCountry;
            t.prospectInterest = latestInterest(c.Prospect__c);
        }

        Id me = v.userId;
        List<Connect_Message__c> msgs;
        if (since == null) {
            msgs = [
                SELECT Id, Body__c, Sender_Type__c, Sender_Display_Name__c, Sender_User__c, Visibility__c, CreatedDate, Client_Message_Id__c
                FROM Connect_Message__c
                WHERE Conversation__c = :conversationId AND (Visibility__c = 'Visible' OR Sender_User__c = :me)
                ORDER BY CreatedDate ASC, Name ASC
                LIMIT 500
            ];
        } else {
            msgs = [
                SELECT Id, Body__c, Sender_Type__c, Sender_Display_Name__c, Sender_User__c, Visibility__c, CreatedDate, Client_Message_Id__c
                FROM Connect_Message__c
                WHERE
                    Conversation__c = :conversationId
                    AND (Visibility__c = 'Visible' OR Sender_User__c = :me)
                    AND (CreatedDate > :since OR LastModifiedDate > :since)
                ORDER BY CreatedDate ASC, Name ASC
                LIMIT 200
            ];
        }
        for (Connect_Message__c m : msgs) {
            t.messages.add(toItem(m, me));
        }

        // Mark as read only when there is something unread (avoids a DML on every poll).
        Boolean unread = role == ROLE_PROSPECT ? c.Prospect_Unread__c : c.Ambassador_Unread__c;
        if (unread == true) {
            markRead(c.Id, role);
        }
        if (role == ROLE_AMBASSADOR) {
            touchAmbassador(c.Ambassador__c);
        }
        return t;
    }

    // ------------------------------------------------------------ start chat

    /** Returns the Id of a new or existing open conversation with the ambassador. */
    public static Id startWithAmbassador(String ambassadorSlugOrId, String origin) {
        LC_Context.Viewer v = LC_Context.requireExternalUser();
        Connect_Ambassador__c amb = LC_DirectoryController.findPublished(ambassadorSlugOrId);
        if (amb == null) {
            throw LC_Context.error('This ambassador is not available at the moment. Please choose someone else.');
        }
        if (amb.Contact__c == v.contactId) {
            throw LC_Context.error('You cannot start a chat with yourself.');
        }
        List<Connect_Conversation__c> existing = [
            SELECT Id
            FROM Connect_Conversation__c
            WHERE Prospect__c = :v.contactId AND Ambassador__c = :amb.Id AND Status__c != 'Closed'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0].Id;
        }
        Integer startedToday = [
            SELECT COUNT()
            FROM Connect_Conversation__c
            WHERE Prospect__c = :v.contactId AND CreatedDate = TODAY
        ];
        if (startedToday >= LC_Settings.maxConversationsPerDay()) {
            throw LC_Context.error('You have started the maximum number of chats for today. Please try again tomorrow.');
        }
        Connect_Conversation__c c = newConversation(v.contactId, 'Ambassador', normaliseOrigin(origin));
        c.Ambassador__c = amb.Id;
        c.Ambassador_Contact__c = amb.Contact__c;
        insert c;

        Connect_Ambassador__c ambUpd = new Connect_Ambassador__c(
            Id = amb.Id,
            Conversations_Count__c = (amb.Conversations_Count__c == null ? 0 : amb.Conversations_Count__c) + 1
        );
        update ambUpd;
        return c.Id;
    }

    /** Creates a staff (admissions team) conversation for the given prospect contact. */
    public static Connect_Conversation__c newConversation(Id prospectContactId, String channelType, String origin) {
        return new Connect_Conversation__c(
            Prospect__c = prospectContactId,
            Channel_Type__c = channelType,
            Status__c = 'Open',
            Origin__c = origin,
            Started_At__c = Datetime.now(),
            Retention_Date__c = Date.today().addMonths(LC_Settings.retentionMonths()),
            OwnerId = LC_Settings.recordOwnerId()
        );
    }

    public static void close(Id conversationId) {
        LC_Context.Viewer v = LC_Context.requireExternalUser();
        Connect_Conversation__c c = loadForParticipant(conversationId, v);
        if (c.Status__c == 'Closed') {
            return;
        }
        update new Connect_Conversation__c(
            Id = c.Id,
            Status__c = 'Closed',
            Closed_At__c = Datetime.now(),
            Closed_Reason__c = 'Prospect request'
        );
        insertSystemMessage(c.Id, 'This chat was closed. You can start a new chat at any time.');
    }

    // ------------------------------------------------------ shared helpers

    public static Connect_Conversation__c loadForParticipant(Id conversationId, LC_Context.Viewer v) {
        if (conversationId == null) {
            throw LC_Context.error('Conversation not found.');
        }
        List<Connect_Conversation__c> rows = [
            SELECT
                Id, Name, Channel_Type__c, Status__c, Prospect__c, Prospect__r.FirstName, Prospect__r.MailingCountry,
                Prospect__r.AccountId, Ambassador__c, Ambassador_Contact__c, Ambassador__r.Display_Name__c,
                Ambassador__r.Photo_Url__c, Ambassador__r.Learning_Program__r.Name, Last_Message_Preview__c,
                Last_Message_By__c, Last_Message_At__c, Prospect_Unread__c, Ambassador_Unread__c, Waiting_Hours__c,
                Started_At__c, First_Response_At__c, Prospect_Age_Band__c, Case__c, Info_Request__c
            FROM Connect_Conversation__c
            WHERE Id = :conversationId
            LIMIT 1
        ];
        if (rows.isEmpty() || (rows[0].Prospect__c != v.contactId && rows[0].Ambassador_Contact__c != v.contactId)) {
            throw LC_Context.error('Conversation not found.');
        }
        return rows[0];
    }

    public static String roleFor(Connect_Conversation__c c, LC_Context.Viewer v) {
        return c.Prospect__c == v.contactId ? ROLE_PROSPECT : ROLE_AMBASSADOR;
    }

    public static Boolean isLocked(String status) {
        return LOCKED_STATUSES.contains(status);
    }

    public static String lockedReason(String status) {
        if (status == 'Closed') {
            return 'This chat is closed.';
        }
        if (status == 'Paused' || status == 'Under Review') {
            return 'This chat is paused while the university team reviews it.';
        }
        return null;
    }

    public static void markRead(Id conversationId, String role) {
        Connect_Conversation__c upd = new Connect_Conversation__c(Id = conversationId);
        if (role == ROLE_PROSPECT) {
            upd.Prospect_Last_Read_At__c = Datetime.now();
        } else {
            upd.Ambassador_Last_Read_At__c = Datetime.now();
        }
        update upd;
    }

    public static Connect_Message__c insertSystemMessage(Id conversationId, String body) {
        Connect_Message__c m = new Connect_Message__c(
            Conversation__c = conversationId,
            Sender_Type__c = 'System',
            Sender_Display_Name__c = 'Launched Connect',
            Body__c = body,
            Visibility__c = 'Visible',
            Moderation_Result__c = 'Allowed',
            Channel__c = 'Web'
        );
        insert m;
        return m;
    }

    public static MessageItem toItem(Connect_Message__c m, Id me) {
        MessageItem i = new MessageItem();
        i.id = m.Id;
        i.body = m.Body__c;
        i.senderType = m.Sender_Type__c;
        i.senderName = m.Sender_Display_Name__c;
        i.mine = m.Sender_User__c == me;
        i.visibility = m.Visibility__c;
        i.sentAt = m.CreatedDate;
        i.clientMessageId = m.Client_Message_Id__c;
        if (i.mine && m.Visibility__c == 'Held') {
            i.notice = 'Being checked by the university before delivery.';
        } else if (i.mine && m.Visibility__c == 'Hidden') {
            i.notice = 'Not delivered: this message did not meet the community guidelines.';
        }
        return i;
    }

    private static ConversationSummary toSummary(Connect_Conversation__c c, String role) {
        ConversationSummary s = new ConversationSummary();
        s.id = c.Id;
        s.name = c.Name;
        s.channelType = c.Channel_Type__c;
        s.status = c.Status__c;
        s.lastMessagePreview = c.Last_Message_Preview__c;
        s.lastMessageBy = c.Last_Message_By__c;
        s.lastMessageAt = c.Last_Message_At__c != null ? c.Last_Message_At__c : c.Started_At__c;
        s.waitingHours = c.Waiting_Hours__c;
        if (role == ROLE_PROSPECT) {
            s.unread = c.Prospect_Unread__c;
            if (c.Channel_Type__c == 'Staff') {
                s.counterpartName = 'Admissions team';
                s.counterpartSubtitle = 'Launched EDX University staff';
            } else {
                s.counterpartName = c.Ambassador__r?.Display_Name__c;
                s.counterpartSubtitle = c.Ambassador__r?.Learning_Program__r?.Name;
                s.counterpartPhotoUrl = c.Ambassador__r?.Photo_Url__c;
            }
        } else {
            s.unread = c.Ambassador_Unread__c;
            s.counterpartName = c.Prospect__r?.FirstName;
            s.counterpartSubtitle = c.Prospect__r?.MailingCountry;
        }
        return s;
    }

    private static String latestInterest(Id contactId) {
        List<AcademicInterest> rows = [
            SELECT LearningProgram.Name, AcademicTerm.Name
            FROM AcademicInterest
            WHERE ContactId = :contactId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (rows.isEmpty() || rows[0].LearningProgram == null) {
            return null;
        }
        String s = rows[0].LearningProgram.Name;
        if (rows[0].AcademicTerm != null) {
            s += ' · ' + rows[0].AcademicTerm.Name;
        }
        return s;
    }

    private static void touchAmbassador(Id ambassadorId) {
        if (ambassadorId == null) {
            return;
        }
        Connect_Ambassador__c a = [SELECT Id, Last_Active__c FROM Connect_Ambassador__c WHERE Id = :ambassadorId LIMIT 1];
        if (a.Last_Active__c == null || a.Last_Active__c < Datetime.now().addMinutes(-5)) {
            update new Connect_Ambassador__c(Id = a.Id, Last_Active__c = Datetime.now());
        }
    }

    private static String normaliseOrigin(String origin) {
        Set<String> allowed = new Set<String>{ 'Profile', 'Directory', 'AI assistant', 'Widget', 'Staff' };
        return allowed.contains(origin) ? origin : 'Profile';
    }
}
