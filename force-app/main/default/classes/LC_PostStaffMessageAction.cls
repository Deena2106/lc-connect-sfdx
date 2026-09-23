/**
 * Invocable action: post a staff message into a Launched Connect conversation.
 * Used by the "Reply in Launched Connect" Case quick action flow and moderation flows.
 */
public with sharing class LC_PostStaffMessageAction {
    public class Request {
        @InvocableVariable(label='Conversation Id' required=true)
        public Id conversationId;
        @InvocableVariable(label='Message' required=true)
        public String body;
        @InvocableVariable(label='Display name (default: Admissions team)')
        public String displayName;
    }

    public class Response {
        @InvocableVariable(label='Message Id')
        public Id messageId;
    }

    @InvocableMethod(label='LC: Post Staff Message' category='Launched Connect')
    public static List<Response> post(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request r : requests) {
            Response res = new Response();
            res.messageId = LC_MessageService.postStaffMessage(r.conversationId, r.body, r.displayName);
            out.add(res);
        }
        return out;
    }
}
