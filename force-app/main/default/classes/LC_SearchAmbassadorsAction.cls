/**
 * Invocable action: search published ambassadors.
 * Reusable by Flow, Agentforce and (Phase 3) a Salesforce Hosted MCP server.
 */
public with sharing class LC_SearchAmbassadorsAction {
    public class Request {
        @InvocableVariable(label='Search text')
        public String searchTerm;
        @InvocableVariable(label='Subject area')
        public String subject;
        @InvocableVariable(label='Study level')
        public String studyLevel;
        @InvocableVariable(label='Home country')
        public String country;
        @InvocableVariable(label='Language')
        public String language;
    }

    public class Response {
        @InvocableVariable(label='Ambassadors (JSON)')
        public String ambassadorsJson;
        @InvocableVariable(label='Total')
        public Integer total;
    }

    @InvocableMethod(label='LC: Search Ambassadors' category='Launched Connect')
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request r : requests) {
            LC_DirectoryController.DirectoryResult res = LC_DirectoryController.searchAmbassadors(
                r.searchTerm, r.subject, r.studyLevel, r.country, r.language, 10, 1
            );
            Response resp = new Response();
            resp.ambassadorsJson = JSON.serialize(res.ambassadors);
            resp.total = res.total;
            out.add(resp);
        }
        return out;
    }
}
