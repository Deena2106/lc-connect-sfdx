
public class LC_CreateAmbassadorUserHandler {
    @future
    public static void createUser(Id ambassadorId) {
        Connect_Ambassador__c ambassador = [SELECT Id,  Contact__c, Contact__r.AccountId, Contact__r.Email, Contact__r.FirstName,  Contact__r.LastName
                                            FROM Connect_Ambassador__c
                                            WHERE Id = :ambassadorId
                                            LIMIT 1];
        if (ambassador.Contact__c == null) {
            return;
        }
        Contact con = ambassador.Contact__r;
        List<User> existingUsers = [ SELECT Id FROM User WHERE ContactId = :con.Id LIMIT 1];
        if (!existingUsers.isEmpty()) {
            return;
        }
        Profile p = [ SELECT Id FROM Profile WHERE Name = 'LC Ambassador' LIMIT 1];
        User u = new User(
            FirstName = con.FirstName,
            LastName = String.isBlank(con.LastName)? 'Ambassador': con.LastName,
            Email = con.Email,
            Username = con.Email.toLowerCase() + '.launchedAmbassador',
            Alias = 'ambass',
            CommunityNickname = 'ambassador' + String.valueOf(DateTime.now().getTime()),
            ProfileId = p.Id,
            ContactId = con.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            IsActive = true
        );
        insert u;
        System.debug('User--->'+u);
        System.debug('Ambassador--->'+ambassador);
        // List<Network> ambassadorNetwork = [SELECT Id, Name FROM Network WHERE Name = 'Ambassador Connect' LIMIT 1];
        // if (!ambassadorNetwork.isEmpty()) {
        //     System.UserManagement.sendAsyncEmailConfirmation(
        //         u.Id,
        //         u.Email,
        //         ambassadorNetwork[0].Id,
        //         '/s/' // This is the start URL they land on after verifying
        //     );
        // }
        EmailTemplate template = [SELECT Id, Name FROM EmailTemplate WHERE Name  = 'LC Ambassador Welcome Email' Limit 1];
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setTemplateId(template.Id);
        email.setTargetObjectId(con.Id);
        if (con.AccountId != null) {
            email.setWhatId(con.AccountId);
        }
        email.setSaveAsActivity(false);
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
        System.debug('Email sent to ambassador--->'+con.Email);
        System.debug('Email message--->'+email);
    }
}