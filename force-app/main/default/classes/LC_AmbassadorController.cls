/**
 * Launched Connect - ambassador inbox and profile editor (Ambassadors audience only).
 */
public without sharing class LC_AmbassadorController {
    private static final Set<String> CONTENT_FIELDS = new Set<String>{
        'Display_Name__c', 'Headline__c', 'Bio__c', 'Interests__c', 'Languages__c', 'Home_Country__c', 'Home_City__c'
    };

    public class Option {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public Option(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class MyProfile {
        @AuraEnabled public Id id;
        @AuraEnabled public String status;
        @AuraEnabled public String displayName;
        @AuraEnabled public String headline;
        @AuraEnabled public String bio;
        @AuraEnabled public List<String> interests;
        @AuraEnabled public List<String> languages;
        @AuraEnabled public String homeCountry;
        @AuraEnabled public String homeCity;
        @AuraEnabled public Boolean livedInHalls;
        @AuraEnabled public Boolean availableForChat;
        @AuraEnabled public String photoUrl;
        @AuraEnabled public String programme;
        @AuraEnabled public String approvalComments;
        @AuraEnabled public List<Option> interestOptions = new List<Option>();
        @AuraEnabled public List<Option> languageOptions = new List<Option>();
    }

    public class ProfileInput {
        @AuraEnabled public String displayName { get; set; }
        @AuraEnabled public String headline { get; set; }
        @AuraEnabled public String bio { get; set; }
        @AuraEnabled public List<String> interests { get; set; }
        @AuraEnabled public List<String> languages { get; set; }
        @AuraEnabled public String homeCountry { get; set; }
        @AuraEnabled public String homeCity { get; set; }
        @AuraEnabled public Boolean livedInHalls { get; set; }
    }

    public class InboxStats {
        @AuraEnabled public Integer awaitingReply = 0;
        @AuraEnabled public Integer avgResponseMinutes;
        @AuraEnabled public Decimal hoursThisMonth;
        @AuraEnabled public Decimal monthlyAllowance;
        @AuraEnabled public Boolean availableForChat;
        @AuraEnabled public String displayName;
        @AuraEnabled public List<LC_ConversationService.ConversationSummary> conversations;
    }

    @AuraEnabled
    public static InboxStats getInbox() {
        LC_Context.Viewer v = requireAmbassador();
        Connect_Ambassador__c a = load(v.ambassadorId);
        InboxStats s = new InboxStats();
        s.displayName = a.Display_Name__c;
        s.availableForChat = a.Available_For_Chat__c;
        s.avgResponseMinutes = a.Avg_First_Response_Minutes__c == null ? null : a.Avg_First_Response_Minutes__c.intValue();
        s.monthlyAllowance = a.Monthly_Hours_Allowance__c;
        Date monthStart = Date.today().toStartOfMonth();
        AggregateResult ar = [
            SELECT SUM(Minutes__c) mins
            FROM Connect_Time_Log__c
            WHERE Ambassador__c = :a.Id AND Activity_Date__c >= :monthStart
        ];
        Decimal mins = (Decimal) ar.get('mins');
        s.hoursThisMonth = mins == null ? 0 : (mins / 60).setScale(1);

        List<LC_ConversationService.ConversationSummary> allConvs = LC_ConversationService.listMine();
        List<LC_ConversationService.ConversationSummary> mine = new List<LC_ConversationService.ConversationSummary>();
        for (LC_ConversationService.ConversationSummary c : allConvs) {
            if (c.channelType == 'Ambassador' && c.counterpartName != null) {
                mine.add(c);
                if (c.lastMessageBy == 'Prospect' && c.status != 'Closed') {
                    s.awaitingReply++;
                }
            }
        }
        s.conversations = mine;
        update new Connect_Ambassador__c(Id = a.Id, Last_Active__c = Datetime.now());
        return s;
    }

    @AuraEnabled
    public static void setAvailability(Boolean available) {
        LC_Context.Viewer v = requireAmbassador();
        update new Connect_Ambassador__c(Id = v.ambassadorId, Available_For_Chat__c = available == true);
    }

    @AuraEnabled
    public static void logTime(Id conversationId, Integer minutes, String activityType, String notes) {
        LC_Context.Viewer v = requireAmbassador();
        if (minutes == null || minutes < 1 || minutes > 480) {
            throw LC_Context.error('Please enter between 1 and 480 minutes.');
        }
        if (conversationId != null) {
            LC_ConversationService.loadForParticipant(conversationId, v);
        }
        insert new Connect_Time_Log__c(
            Ambassador__c = v.ambassadorId,
            Conversation__c = conversationId,
            Activity_Date__c = Date.today(),
            Minutes__c = minutes,
            Activity_Type__c = String.isBlank(activityType) ? 'Chat' : activityType,
            Notes__c = notes == null ? null : notes.left(255)
        );
    }

    @AuraEnabled
    public static MyProfile getMyProfile() {
        LC_Context.Viewer v = requireAmbassador();
        Connect_Ambassador__c a = load(v.ambassadorId);
        MyProfile p = new MyProfile();
        p.id = a.Id;
        p.status = a.Status__c;
        p.displayName = a.Display_Name__c;
        p.headline = a.Headline__c;
        p.bio = a.Bio__c;
        p.interests = split(a.Interests__c);
        p.languages = split(a.Languages__c);
        p.homeCountry = a.Home_Country__c;
        p.homeCity = a.Home_City__c;
        p.livedInHalls = a.Lived_In_Halls__c;
        p.availableForChat = a.Available_For_Chat__c;
        p.photoUrl = a.Photo_Url__c;
        p.programme = a.Learning_Program__r?.Name;
        p.approvalComments = a.Approval_Comments__c;
        for (Schema.PicklistEntry e : Connect_Ambassador__c.Interests__c.getDescribe().getPicklistValues()) {
            if (e.isActive()) {
                p.interestOptions.add(new Option(e.getLabel(), e.getValue()));
            }
        }
        for (Schema.PicklistEntry e : Connect_Ambassador__c.Languages__c.getDescribe().getPicklistValues()) {
            if (e.isActive()) {
                p.languageOptions.add(new Option(e.getLabel(), e.getValue()));
            }
        }
        return p;
    }

    /** Saves the ambassador's own profile. Content changes send it back for review. Returns the new status. */
    @AuraEnabled
    public static String saveMyProfile(ProfileInput input) {
        LC_Context.Viewer v = requireAmbassador();
        if (input == null || String.isBlank(input.displayName)) {
            throw LC_Context.error('Please enter a display name.');
        }
        if (input.interests != null && input.interests.size() > 5) {
            throw LC_Context.error('Please choose up to five interests.');
        }
        Connect_Ambassador__c existing = load(v.ambassadorId);
        Connect_Ambassador__c upd = new Connect_Ambassador__c(
            Id = existing.Id,
            Display_Name__c = input.displayName.trim().left(40),
            Headline__c = input.headline == null ? null : input.headline.trim().left(80),
            Bio__c = input.bio == null ? null : input.bio.trim().left(2000),
            Interests__c = input.interests == null ? null : String.join(input.interests, ';'),
            Languages__c = input.languages == null ? null : String.join(input.languages, ';'),
            Home_Country__c = input.homeCountry == null ? null : input.homeCountry.trim().left(80),
            Home_City__c = input.homeCity == null ? null : input.homeCity.trim().left(80),
            Lived_In_Halls__c = input.livedInHalls == true
        );
        Boolean contentChanged = false;
        for (String f : CONTENT_FIELDS) {
            if (asText(existing.get(f)) != asText(upd.get(f))) {
                contentChanged = true;
            }
        }
        String status = existing.Status__c;
        if (contentChanged && (status == 'Draft' || status == 'Published')) {
            status = 'In Review';
            upd.Status__c = status;
        }
        update upd;
        return status;
    }

    // ---------------------------------------------------------------- helpers

    private static LC_Context.Viewer requireAmbassador() {
        LC_Context.Viewer v = LC_Context.requireExternalUser();
        if (!v.isAmbassador) {
            throw LC_Context.error('This page is for student ambassadors.');
        }
        return v;
    }

    private static Connect_Ambassador__c load(Id ambassadorId) {
        return [
            SELECT
                Id, Status__c, Display_Name__c, Headline__c, Bio__c, Interests__c, Languages__c, Home_Country__c,
                Home_City__c, Lived_In_Halls__c, Available_For_Chat__c, Photo_Url__c, Learning_Program__r.Name,
                Approval_Comments__c, Avg_First_Response_Minutes__c, Monthly_Hours_Allowance__c
            FROM Connect_Ambassador__c
            WHERE Id = :ambassadorId
            LIMIT 1
        ];
    }

    private static String asText(Object value) {
        return value == null ? '' : String.valueOf(value);
    }

    private static List<String> split(String value) {
        return String.isBlank(value) ? new List<String>() : value.split(';');
    }
}
