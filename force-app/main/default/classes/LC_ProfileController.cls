/**
 * Launched Connect - the "About you" step after a prospect first logs in.
 * Updates the prospect's own Person Account, Contact Profile and Academic Interest.
 * Without sharing, but every write is scoped to the running user's own records.
 */
public without sharing class LC_ProfileController {
    public class Option {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public Option(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class ViewerInfo {
        @AuraEnabled public Boolean isGuest;
        @AuraEnabled public Boolean isAmbassador;
        @AuraEnabled public Boolean profileComplete;
        @AuraEnabled public String firstName;
        @AuraEnabled public Integer pollSeconds;
    }

    public class RegistrationContext {
        @AuraEnabled public Boolean profileComplete;
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public String country;
        @AuraEnabled public Date birthdate;
        @AuraEnabled public List<Option> programmes = new List<Option>();
        @AuraEnabled public List<Option> terms = new List<Option>();
        @AuraEnabled public String guidelinesVersion;
        @AuraEnabled public Integer minimumAge;
    }

    public class RegistrationInput {
        @AuraEnabled public String firstName { get; set; }
        @AuraEnabled public String lastName { get; set; }
        @AuraEnabled public String country { get; set; }
        @AuraEnabled public Date birthdate { get; set; }
        @AuraEnabled public String programmeId { get; set; }
        @AuraEnabled public String termId { get; set; }
        @AuraEnabled public Boolean acceptGuidelines { get; set; }
        @AuraEnabled public Boolean marketingOptIn { get; set; }
        @AuraEnabled public String ambassador { get; set; }
        @AuraEnabled public String source { get; set; }
        @AuraEnabled public String utmSource { get; set; }
        @AuraEnabled public String utmMedium { get; set; }
        @AuraEnabled public String utmCampaign { get; set; }
    }

    @AuraEnabled
    public static ViewerInfo getViewer() {
        LC_Context.Viewer v = LC_Context.current();
        ViewerInfo info = new ViewerInfo();
        info.isGuest = v.isGuest;
        info.isAmbassador = v.isAmbassador;
        info.firstName = v.firstName;
        info.pollSeconds = LC_Settings.pollSeconds();
        info.profileComplete = false;
        if (v.isAmbassador) {
            info.profileComplete = true;
        } else if (v.accountId != null) {
            Account a = [SELECT Connect_Profile_Complete__c FROM Account WHERE Id = :v.accountId LIMIT 1];
            info.profileComplete = a.Connect_Profile_Complete__c;
        }
        return info;
    }

    @AuraEnabled
    public static RegistrationContext getRegistrationContext() {
        LC_Context.Viewer v = LC_Context.requireExternalUser();
        Account a = [
            SELECT FirstName, LastName, PersonMailingCountry, PersonBirthdate, Connect_Profile_Complete__c
            FROM Account
            WHERE Id = :v.accountId
            LIMIT 1
        ];
        RegistrationContext ctx = new RegistrationContext();
        ctx.profileComplete = a.Connect_Profile_Complete__c;
        ctx.firstName = a.FirstName;
        ctx.lastName = a.LastName;
        ctx.country = a.PersonMailingCountry;
        ctx.birthdate = a.PersonBirthdate;
        ctx.guidelinesVersion = LC_Settings.guidelinesVersion();
        ctx.minimumAge = LC_Settings.minimumAge();
        for (LearningProgram lp : [SELECT Id, Name FROM LearningProgram ORDER BY Name LIMIT 1000]) {
            ctx.programmes.add(new Option(lp.Name, lp.Id));
        }
        for (AcademicTerm t : [SELECT Id, Name FROM AcademicTerm WHERE StartDate >= TODAY ORDER BY StartDate LIMIT 20]) {
            ctx.terms.add(new Option(t.Name, t.Id));
        }
        return ctx;
    }

    @AuraEnabled
    public static void completeRegistration(RegistrationInput input) {
        LC_Context.Viewer v = LC_Context.requireExternalUser();
        if (input == null) {
            throw LC_Context.error('Please complete the form.');
        }
        if (input.acceptGuidelines != true) {
            throw LC_Context.error('Please accept the community guidelines to continue.');
        }
        if (String.isBlank(input.firstName) || String.isBlank(input.lastName)) {
            throw LC_Context.error('Please enter your first and last name.');
        }
        if (String.isBlank(input.country)) {
            throw LC_Context.error('Please choose your country of residence.');
        }
        if (input.birthdate == null || input.birthdate > Date.today()) {
            throw LC_Context.error('Please enter your date of birth.');
        }
        if (input.birthdate.addYears(LC_Settings.minimumAge()) > Date.today()) {
            throw LC_Context.error(
                'Sorry, you need to be at least ' + LC_Settings.minimumAge() +
                ' to use Launched Connect. Please ask a parent, carer or teacher to contact the university.'
            );
        }

        Datetime now = Datetime.now();
        Account acc = [SELECT Id, Connect_Registered_Date__c, Connect_First_Ambassador__c FROM Account WHERE Id = :v.accountId LIMIT 1];
        Account upd = new Account(
            Id = acc.Id,
            FirstName = input.firstName.trim().left(40),
            LastName = input.lastName.trim().left(80),
            PersonMailingCountry = input.country.left(80),
            PersonBirthdate = input.birthdate,
            Connect_Status__c = 'Active',
            Connect_Profile_Complete__c = true,
            Connect_Marketing_Opt_In__c = input.marketingOptIn == true,
            Connect_Source__c = normaliseSource(input.source),
            UTM_Source__c = clip(input.utmSource),
            UTM_Medium__c = clip(input.utmMedium),
            UTM_Campaign__c = clip(input.utmCampaign)
        );
        if (acc.Connect_Registered_Date__c == null) {
            upd.Connect_Registered_Date__c = now;
        }
        if (acc.Connect_First_Ambassador__c == null && String.isNotBlank(input.ambassador)) {
            Connect_Ambassador__c amb = LC_DirectoryController.findPublished(input.ambassador);
            if (amb != null) {
                upd.Connect_First_Ambassador__c = amb.Id;
            }
        }
        update upd;

        // Contact Profile (one per contact).
        List<ContactProfile> profiles = [SELECT Id FROM ContactProfile WHERE ContactId = :v.contactId LIMIT 1];
        ContactProfile cp = profiles.isEmpty() ? new ContactProfile(ContactId = v.contactId) : profiles[0];
        cp.Connect_Guidelines_Version__c = LC_Settings.guidelinesVersion();
        cp.Connect_Guidelines_Accepted__c = now;
        upsert cp;

        // Academic Interest (skip if the same programme and term already exists).
        if (String.isNotBlank(input.programmeId)) {
            Id programmeId = Id.valueOf(input.programmeId);
            Id termId = String.isBlank(input.termId) ? null : Id.valueOf(input.termId);
            Integer existing = [
                SELECT COUNT()
                FROM AcademicInterest
                WHERE ContactId = :v.contactId AND LearningProgramId = :programmeId AND AcademicTermId = :termId
            ];
            if (existing == 0) {
                insert new AcademicInterest(
                    AccountId = v.accountId,
                    ContactId = v.contactId,
                    LearningProgramId = programmeId,
                    AcademicTermId = termId,
                    ReceivedDate = Date.today(),
                    OwnerId = LC_Settings.recordOwnerId()
                );
            }
        }
    }

    private static String clip(String s) {
        return String.isBlank(s) ? null : s.trim().left(100);
    }

    private static String normaliseSource(String source) {
        Set<String> allowed = new Set<String>{ 'Profile', 'Directory', 'Campaign', 'AI assistant', 'Widget' };
        return allowed.contains(source) ? source : 'Directory';
    }
}
