public class LC_CreateAmbassadorUser {
	@InvocableMethod(label='Create Ambassador User')
    public static void createUser(List<Request> requests) {
        for (Request req : requests) {
            LC_CreateAmbassadorUserHandler.createUser(req.ambassadorId);
        }
    }
    public class Request {
        @InvocableVariable(required=true)
        public Id ambassadorId;
    }
}