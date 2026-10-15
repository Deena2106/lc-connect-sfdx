/**
 * Launched Connect - unit tests for the LWR page controllers and services.
 */
@IsTest
private class LC_Tests {
    @TestSetup
    static void setup() {
        User admin;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            admin = LC_TestFactory.adminWithRole();
        }
        Account prospectAccount;
        Account ambassadorAccount;
        System.runAs(admin) {
            prospectAccount = LC_TestFactory.personAccount('Sam', 'Rivera', admin.Id, Date.today().addYears(-19));
            ambassadorAccount = LC_TestFactory.personAccount('Ada', 'Okafor', admin.Id, Date.today().addYears(-20));
        }
        System.runAs(admin) {
            LC_TestFactory.communityUser(prospectAccount, 'LC Prospect');
            LC_TestFactory.communityUser(ambassadorAccount, 'LC Ambassador');
        }
        System.runAs(admin) {
            LC_TestFactory.ambassador(ambassadorAccount.PersonContactId);
        }
    }

    // ---------------------------------------------------------------- helpers

    private static User admin() {
        return [SELECT Id, Username FROM User WHERE Email = 'lc.admin@example.com' AND IsActive = TRUE ORDER BY CreatedDate DESC LIMIT 1];
    }

    private static User userFor(String firstName) {
        return [SELECT Id FROM User WHERE FirstName = :firstName AND ContactId != NULL AND Email LIKE '%@example.com' ORDER BY CreatedDate DESC LIMIT 1];
    }

    private static void configure() {
        LC_Settings.setForTest(LC_TestFactory.settings(admin().Username));
        LC_ModerationService.testRules = LC_TestFactory.rules();
        LC_Context.reset();
    }

    private static LC_ProfileController.RegistrationInput registration() {
        LC_ProfileController.RegistrationInput input = new LC_ProfileController.RegistrationInput();
        input.firstName = 'Sam';
        input.lastName = 'Rivera';
        input.country = 'Spain';
        input.birthdate = Date.today().addYears(-19);
        input.acceptGuidelines = true;
        input.marketingOptIn = true;
        input.ambassador = LC_TestFactory.AMBASSADOR_SLUG;
        input.source = 'Profile';
        input.utmSource = 'instagram';
        return input;
    }

    // ------------------------------------------------------------------ tests

    @IsTest
    static void moderationHoldsContactDetailsAndAllowsUniversityLinks() {
        configure();
        Test.startTest();
        LC_ModerationService.Result phone = LC_ModerationService.evaluate('call me on +44 7700 900123', 'Prospect');
        LC_ModerationService.Result uniLink = LC_ModerationService.evaluate('see https://www.launchededx.ac.uk/halls', 'Ambassador');
        LC_ModerationService.Result otherLink = LC_ModerationService.evaluate('see https://example.org', 'Ambassador');
        LC_ModerationService.Result clean = LC_ModerationService.evaluate('What are the halls like?', 'Prospect');
        LC_ModerationService.Result staff = LC_ModerationService.evaluate('call +44 7700 900123', 'Staff');
        Test.stopTest();

        Assert.areEqual(LC_ModerationService.HOLD, phone.action);
        Assert.areEqual('Contact details', phone.reason);
        Assert.areEqual(LC_ModerationService.ALLOW, uniLink.action, 'University links are allowed');
        Assert.areEqual(LC_ModerationService.HOLD, otherLink.action);
        Assert.areEqual(LC_ModerationService.ALLOW, clean.action);
        Assert.areEqual(LC_ModerationService.ALLOW, staff.action, 'Staff messages are not screened');
        Assert.areEqual(3, LC_ModerationService.rank('High'));
    }

    @IsTest
    static void directoryReturnsPublishedAmbassadors() {
        configure();
        Test.startTest();
        LC_DirectoryController.DirectoryResult everyone = LC_DirectoryController.searchAmbassadors(null, null, null, null, null, 12, 1);
        LC_DirectoryController.DirectoryResult filtered = LC_DirectoryController.searchAmbassadors('gaming', 'Computing', 'Undergraduate', 'Nigeria', 'Yoruba', 12, 1);
        LC_DirectoryController.DirectoryResult noMatches = LC_DirectoryController.searchAmbassadors(null, 'Medicine', null, null, null, 12, 1);
        LC_DirectoryController.AmbassadorCard card = LC_DirectoryController.getAmbassador(LC_TestFactory.AMBASSADOR_SLUG);
        LC_DirectoryController.FilterOptions options = LC_DirectoryController.getFilterOptions();
        LC_SearchAmbassadorsAction.Request req = new LC_SearchAmbassadorsAction.Request();
        req.subject = 'Computing';
        List<LC_SearchAmbassadorsAction.Response> actionResult = LC_SearchAmbassadorsAction.run(new List<LC_SearchAmbassadorsAction.Request>{ req });
        Test.stopTest();

        Assert.areEqual(1, everyone.total);
        Assert.areEqual(1, filtered.total);
        Assert.areEqual(0, noMatches.total);
        Assert.areEqual('Ada', card.displayName);
        Assert.isNotNull(card.bio, 'Profile view includes the bio');
        Assert.isTrue(card.online);
        Assert.areEqual(1, options.subjects.size());
        Assert.areEqual(1, actionResult[0].total);
    }

    @IsTest
    static void prospectRegistersAndChats() {
        configure();
        User prospect = userFor('Sam');
        Id conversationId;
        Test.startTest();
        System.runAs(prospect) {
            LC_Context.reset();
            LC_ProfileController.ViewerInfo startInfo = LC_ProfileController.getViewer();
            Assert.isFalse(startInfo.profileComplete);
            LC_ProfileController.RegistrationContext ctx = LC_ProfileController.getRegistrationContext();
            Assert.areEqual('Sam', ctx.firstName);
            LC_ProfileController.completeRegistration(registration());
            Assert.isTrue(LC_ProfileController.getViewer().profileComplete);

            conversationId = LC_ChatController.startConversation(LC_TestFactory.AMBASSADOR_SLUG, 'Profile');
            Assert.areEqual(conversationId, LC_ChatController.startConversation(LC_TestFactory.AMBASSADOR_SLUG, 'Profile'), 'Re-uses open chat');

            LC_MessageService.SendResult sent = LC_ChatController.sendMessage(conversationId, 'Is the first year maths heavy?', 'client-1');
            Assert.isFalse(sent.held);
            LC_MessageService.SendResult again = LC_ChatController.sendMessage(conversationId, 'Is the first year maths heavy?', 'client-1');
            Assert.areEqual(sent.message.id, again.message.id, 'Duplicate send is ignored');

            List<LC_ConversationService.ConversationSummary> mine = LC_ChatController.listMyConversations();
            Assert.areEqual(1, mine.size());
            Assert.areEqual('Ada', mine[0].counterpartName);

            LC_ConversationService.Thread t = LC_ChatController.getThread(conversationId, null);
            Assert.areEqual('Prospect', t.role);
            Assert.areEqual(1, t.messages.size());
            Assert.isTrue(t.canSend);
        }

        User ambassador = userFor('Ada');
        System.runAs(ambassador) {
            LC_Context.reset();
            LC_AmbassadorController.InboxStats inbox = LC_AmbassadorController.getInbox();
            Assert.areEqual(1, inbox.awaitingReply);
            LC_ConversationService.Thread t = LC_ChatController.getThread(conversationId, null);
            Assert.areEqual('Ambassador', t.role);
            Assert.areEqual('Spain', t.prospectCountry);
            Assert.areEqual('Sam', t.conversation.counterpartName);
            LC_ChatController.sendMessage(conversationId, 'Not really, there is lots of support.', 'client-2');
            LC_AmbassadorController.logTime(conversationId, 10, 'Chat', 'Reply to Sam');
            Id staffConversation = LC_ChatController.referToAdmissions(conversationId, 'Tuition Fee', 'Asked about fees');
            Assert.isNotNull(staffConversation);
        }
        Test.stopTest();

        Connect_Conversation__c c = [
            SELECT Status__c, First_Response_Minutes__c, Last_Message_By__c, Message_Count__c
            FROM Connect_Conversation__c
            WHERE Id = :conversationId
        ];
        Assert.areEqual('Ambassador', c.Last_Message_By__c);
        Assert.isNotNull(c.First_Response_Minutes__c);
        Assert.areEqual(1, [SELECT COUNT() FROM Connect_Time_Log__c]);
        Account acc = [SELECT Connect_Status__c, Connect_First_Ambassador__c, UTM_Source__c FROM Account WHERE FirstName = 'Sam' LIMIT 1];
        Assert.areEqual('Active', acc.Connect_Status__c);
        Assert.isNotNull(acc.Connect_First_Ambassador__c);
        Assert.areEqual('instagram', acc.UTM_Source__c);
    }

    @IsTest
    static void heldMessagesAreFlaggedAndHidden() {
        configure();
        User prospect = userFor('Sam');
        Id conversationId;
        Test.startTest();
        System.runAs(prospect) {
            LC_Context.reset();
            conversationId = LC_ChatController.startConversation(LC_TestFactory.AMBASSADOR_SLUG, 'Directory');
            LC_MessageService.SendResult res = LC_ChatController.sendMessage(conversationId, 'text me on 07700 900123', null);
            Assert.isTrue(res.held);
            Assert.isNotNull(res.notice);
            Assert.isNotNull(res.message.notice, 'Sender sees a held notice');
            LC_ChatController.reportConcern(conversationId, null, 'Other', 'Testing the report button');
        }
        System.runAs(userFor('Ada')) {
            LC_Context.reset();
            LC_ConversationService.Thread t = LC_ChatController.getThread(conversationId, null);
            Assert.areEqual(0, t.messages.size(), 'Ambassador cannot see held message');
        }
        Test.stopTest();
        Assert.areEqual(2, [SELECT COUNT() FROM Connect_Flag__c WHERE Conversation__c = :conversationId]);
        Assert.areEqual(2, [SELECT Open_Flag_Count__c FROM Connect_Conversation__c WHERE Id = :conversationId].Open_Flag_Count__c.intValue());
    }

    @IsTest
    static void highSeverityFlagPausesConversation() {
        configure();
        Id conversationId;
        Test.startTest();
        System.runAs(userFor('Sam')) {
            LC_Context.reset();
            conversationId = LC_ChatController.startConversation(LC_TestFactory.AMBASSADOR_SLUG, 'Profile');
            LC_ChatController.sendMessage(conversationId, 'I feel unsafe', null);
            try {
                LC_ChatController.sendMessage(conversationId, 'hello?', null);
                Assert.fail('Expected the conversation to be locked');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('paused'));
            }
        }
        Test.stopTest();
        Assert.areEqual('Under Review', [SELECT Status__c FROM Connect_Conversation__c WHERE Id = :conversationId].Status__c);
    }

    @IsTest
    static void prospectCanAskAdmissionsAndClose() {
        configure();
        Test.startTest();
        System.runAs(userFor('Sam')) {
            LC_Context.reset();
            Id staffConv = LC_ChatController.askAdmissions('Application Process', 'What grades do I need?');
            Assert.isNotNull(staffConv);
            List<LC_ConversationService.ConversationSummary> mine = LC_ChatController.listMyConversations();
            Assert.areEqual('Admissions team', mine[0].counterpartName);
            LC_ChatController.closeConversation(staffConv);
            try {
                LC_ChatController.askAdmissions('Housing', 'no');
                Assert.fail('Short questions are rejected');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('question'));
            }
        }
        Test.stopTest();
        Assert.areEqual(1, [SELECT COUNT() FROM Case WHERE Subject LIKE 'Launched Connect:%']);
        Assert.areEqual('Closed', [SELECT Status__c FROM Connect_Conversation__c WHERE Channel_Type__c = 'Staff' LIMIT 1].Status__c);
    }

    @IsTest
    static void ambassadorEditsProfile() {
        configure();
        Test.startTest();
        System.runAs(userFor('Ada')) {
            LC_Context.reset();
            LC_AmbassadorController.MyProfile p = LC_AmbassadorController.getMyProfile();
            Assert.areEqual('Published', p.status);
            LC_AmbassadorController.ProfileInput input = new LC_AmbassadorController.ProfileInput();
            input.displayName = 'Ada';
            input.headline = 'Computer Science, Year 2';
            input.bio = 'Updated bio';
            input.interests = new List<String>{ 'Gaming' };
            input.languages = new List<String>{ 'English' };
            input.homeCountry = 'Nigeria';
            input.livedInHalls = true;
            String status = LC_AmbassadorController.saveMyProfile(input);
            Assert.areEqual('In Review', status);
            LC_AmbassadorController.setAvailability(false);
        }
        Test.stopTest();
        Connect_Ambassador__c a = [SELECT Status__c, Available_For_Chat__c, Bio__c FROM Connect_Ambassador__c LIMIT 1];
        Assert.areEqual('In Review', a.Status__c);
        Assert.isFalse(a.Available_For_Chat__c);
        Assert.areEqual('Updated bio', a.Bio__c);
    }

    @IsTest
    static void guestsAndStrangersAreBlocked() {
        configure();
        Test.startTest();
        System.runAs(userFor('Sam')) {
            LC_Context.reset();
            try {
                LC_AmbassadorController.getMyProfile();
                Assert.fail('Prospects cannot use ambassador pages');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('ambassadors'));
            }
            try {
                LC_ChatController.getThread(null, null);
                Assert.fail('Missing conversation');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('not found'));
            }
        }
        LC_Context.reset();
        try {
            LC_ChatController.listMyConversations();
            Assert.fail('Internal users have no contact');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('log in'));
        }
        Test.stopTest();
    }

    @IsTest
    static void authHelpersValidateInput() {
        configure();
        Test.startTest();
        LC_AuthController.StartResult unknown = LC_AuthController.startLogin('new.person@example.com');
        LC_AuthController.StartResult reg = LC_AuthController.startRegistration('New', 'Person', 'new.person@example.com');
        Test.stopTest();
        Assert.areEqual('register', unknown.mode);
        Assert.areEqual('register', reg.mode);
        Assert.areEqual('/', LC_AuthController.safeStartUrl('https://evil.example.com'));
        Assert.areEqual('/', LC_AuthController.safeStartUrl('//evil.example.com'));
        Assert.areEqual('/connect/messages', LC_AuthController.safeStartUrl('/connect/messages'));
        try {
            LC_AuthController.normaliseEmail('not-an-email');
            Assert.fail('Invalid email should throw');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('valid email'));
        }
        try {
            LC_AuthController.verifyLogin(null, null, null, '/');
            Assert.fail('Missing code should throw');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('code'));
        }
    }

    @IsTest
    static void staffCanPostMessages() {
        configure();
        Id conversationId;
        System.runAs(userFor('Sam')) {
            LC_Context.reset();
            conversationId = LC_ChatController.startConversation(LC_TestFactory.AMBASSADOR_SLUG, 'Profile');
        }
        LC_Context.reset();
        LC_PostStaffMessageAction.Request req = new LC_PostStaffMessageAction.Request();
        req.conversationId = conversationId;
        req.body = 'Hi Sam, a reminder to keep chats on Launched Connect.';
        Test.startTest();
        List<LC_PostStaffMessageAction.Response> res = LC_PostStaffMessageAction.post(new List<LC_PostStaffMessageAction.Request>{ req });
        Test.stopTest();
        Assert.isNotNull(res[0].messageId);
        Assert.areEqual('Staff', [SELECT Last_Message_By__c FROM Connect_Conversation__c WHERE Id = :conversationId].Last_Message_By__c);
    }
}