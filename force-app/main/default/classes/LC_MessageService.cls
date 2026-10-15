/**
 * Launched Connect - sending messages (prospects and ambassadors) and staff messages.
 */
public without sharing class LC_MessageService {
    public static final Integer MAX_LENGTH = 4000;

    public class SendResult {
        @AuraEnabled public LC_ConversationService.MessageItem message;
        @AuraEnabled public Boolean held = false;
        @AuraEnabled public String notice;
    }

    public static SendResult send(Id conversationId, String body, String clientMessageId, String channel) {
        LC_Context.Viewer v = LC_Context.requireExternalUser();
        Connect_Conversation__c c = LC_ConversationService.loadForParticipant(conversationId, v);
        String role = LC_ConversationService.roleFor(c, v);

        if (LC_ConversationService.isLocked(c.Status__c)) {
            throw LC_Context.error(LC_ConversationService.lockedReason(c.Status__c));
        }
        String text = body == null ? '' : body.trim();
        if (String.isBlank(text)) {
            throw LC_Context.error('Please type a message.');
        }
        if (text.length() > MAX_LENGTH) {
            throw LC_Context.error('Messages can be up to ' + MAX_LENGTH + ' characters.');
        }

        // Idempotency: the browser retries with the same client id.
        if (String.isNotBlank(clientMessageId)) {
            List<Connect_Message__c> dup = [
                SELECT Id, Body__c, Sender_Type__c, Sender_Display_Name__c, Sender_User__c, Visibility__c, CreatedDate, Client_Message_Id__c
                FROM Connect_Message__c
                WHERE Client_Message_Id__c = :clientMessageId
                LIMIT 1
            ];
            if (!dup.isEmpty()) {
                SendResult again = new SendResult();
                again.message = LC_ConversationService.toItem(dup[0], v.userId);
                again.held = dup[0].Visibility__c != 'Visible';
                return again;
            }
        }

        // Rate limit per sender.
        Datetime oneMinuteAgo = Datetime.now().addMinutes(-1);
        Integer recent = [
            SELECT COUNT()
            FROM Connect_Message__c
            WHERE Sender_User__c = :v.userId AND CreatedDate >= :oneMinuteAgo
        ];
        if (recent >= LC_Settings.maxMessagesPerMinute()) {
            throw LC_Context.error('You are sending messages very quickly. Please wait a moment.');
        }

        LC_ModerationService.Result mod = LC_ModerationService.evaluate(text, role);
        Boolean held = mod.action == LC_ModerationService.HOLD;

        Connect_Message__c m = new Connect_Message__c(
            Conversation__c = c.Id,
            Sender_Type__c = role,
            Sender_User__c = v.userId,
            Sender_Display_Name__c = role == LC_ConversationService.ROLE_AMBASSADOR ? v.ambassadorName : v.firstName,
            Body__c = text,
            Visibility__c = held ? 'Held' : 'Visible',
            Moderation_Result__c = mod.action == LC_ModerationService.ALLOW ? 'Allowed' : (held ? 'Held' : 'Flagged'),
            Moderation_Reason__c = mod.matched.isEmpty() ? null : String.join(mod.matched, ', ').left(255),
            Channel__c = normaliseChannel(channel),
            Client_Message_Id__c = String.isBlank(clientMessageId) ? null : clientMessageId.left(64)
        );
        insert m;

        if (mod.action != LC_ModerationService.ALLOW) {
            LC_ModerationService.createFlag(c.Id, m.Id, 'Auto rule', mod.reason, mod.severity, mod.ruleName, null, null);
        }
        if (!held) {
            afterVisibleMessage(c, m, role);
        }
        publish(c.Id, m);

        m = [
            SELECT Id, Body__c, Sender_Type__c, Sender_Display_Name__c, Sender_User__c, Visibility__c, CreatedDate, Client_Message_Id__c
            FROM Connect_Message__c
            WHERE Id = :m.Id
        ];
        SendResult res = new SendResult();
        res.message = LC_ConversationService.toItem(m, v.userId);
        res.held = held;
        res.notice = held ? mod.messageToSender : null;
        return res;
    }

    /** Posts a message from university staff (internal users), e.g. from the console or a flow. */
    public static Id postStaffMessage(Id conversationId, String body, String displayName) {
        if (String.isBlank(body)) {
            throw LC_Context.error('Message is empty.');
        }
        Connect_Conversation__c c = [
            SELECT Id, Status__c, Started_At__c, First_Response_At__c, Prospect__r.AccountId, Ambassador__c
            FROM Connect_Conversation__c
            WHERE Id = :conversationId
            LIMIT 1
        ];
        Connect_Message__c m = new Connect_Message__c(
            Conversation__c = c.Id,
            Sender_Type__c = 'Staff',
            Sender_User__c = UserInfo.getUserId(),
            Sender_Display_Name__c = String.isBlank(displayName) ? 'Admissions team' : displayName,
            Body__c = body.trim().left(MAX_LENGTH),
            Visibility__c = 'Visible',
            Moderation_Result__c = 'Allowed',
            Channel__c = 'Staff console'
        );
        insert m;
        afterVisibleMessage(c, m, 'Staff');
        publish(c.Id, m);
        return m.Id;
    }

    // ---------------------------------------------------------------- helpers

    public static void afterVisibleMessage(Connect_Conversation__c c, Connect_Message__c m, String role) {
        Datetime now = Datetime.now();
        Connect_Conversation__c upd = new Connect_Conversation__c(
            Id = c.Id,
            Last_Message_At__c = now,
            Last_Message_By__c = role,
            Last_Message_Preview__c = m.Body__c.replaceAll('\\s+', ' ').abbreviate(120)
        );
        if (role == LC_ConversationService.ROLE_PROSPECT) {
            upd.Prospect_Last_Read_At__c = now;
            if (c.Status__c == 'Open') {
                upd.Status__c = 'Awaiting Reply';
            }
            if (c.Prospect__r != null && c.Prospect__r.AccountId != null) {
                update new Account(Id = c.Prospect__r.AccountId, Connect_Last_Activity__c = now);
            }
        } else {
            upd.Ambassador_Last_Read_At__c = now;
            if (c.Status__c == 'Awaiting Reply') {
                upd.Status__c = 'Open';
            }
            if (c.First_Response_At__c == null) {
                List<Connect_Message__c> firstProspect = [
                    SELECT CreatedDate
                    FROM Connect_Message__c
                    WHERE Conversation__c = :c.Id AND Sender_Type__c = 'Prospect'
                    ORDER BY CreatedDate ASC
                    LIMIT 1
                ];
                if (!firstProspect.isEmpty()) {
                    upd.First_Response_At__c = now;
                    Long mins = (now.getTime() - firstProspect[0].CreatedDate.getTime()) / 60000;
                    upd.First_Response_Minutes__c = mins;
                }
            }
            if (role == LC_ConversationService.ROLE_AMBASSADOR && c.Ambassador__c != null) {
                update new Connect_Ambassador__c(Id = c.Ambassador__c, Last_Active__c = now);
            }
        }
        update upd;
    }

    private static void publish(Id conversationId, Connect_Message__c m) {
        EventBus.publish(
            new LC_Message_Event__e(
                Conversation_Id__c = conversationId,
                Message_Id__c = m.Id,
                Sender_Type__c = m.Sender_Type__c,
                Visibility__c = m.Visibility__c
            )
        );
    }

    private static String normaliseChannel(String channel) {
        Set<String> allowed = new Set<String>{ 'Web', 'AI assistant', 'Widget' };
        return allowed.contains(channel) ? channel : 'Web';
    }
}