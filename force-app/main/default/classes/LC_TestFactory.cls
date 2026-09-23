/**
 * Launched Connect - test data. Uses generated, fictional data only.
 */
@IsTest
public class LC_TestFactory {
    public static final String AMBASSADOR_SLUG = 'ada-test';

    private static Integer counter = 0;

    public static String unique() {
        counter++;
        return String.valueOf(Datetime.now().getTime()) + String.valueOf(counter);
    }

    /** System administrator with a role (portal account owners must have a role). */
    public static User adminWithRole() {
        UserRole role = new UserRole(Name = 'LC Test Role', DeveloperName = 'LC_Test_Role_' + unique());
        insert role;
        Profile p = [SELECT Id FROM Profile WHERE PermissionsModifyAllData = TRUE AND UserType = 'Standard' ORDER BY CreatedDate LIMIT 1];
        User u = new User(
            Alias = 'lcadm',
            Email = 'lc.admin@example.com',
            EmailEncodingKey = 'UTF-8',
            FirstName = 'Test',
            LastName = 'Admin',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_GB',
            ProfileId = p.Id,
            TimeZoneSidKey = 'Europe/London',
            Username = 'lc.admin.' + unique() + '@example.com',
            UserRoleId = role.Id
        );
        insert u;
        return u;
    }

    public static Id personRecordTypeId() {
        return [SELECT Id FROM RecordType WHERE SobjectType = 'Account' AND IsPersonType = TRUE AND IsActive = TRUE LIMIT 1].Id;
    }

    public static Account personAccount(String firstName, String lastName, Id ownerId, Date birthdate) {
        Account a = new Account(
            RecordTypeId = personRecordTypeId(),
            FirstName = firstName,
            LastName = lastName,
            PersonEmail = firstName.toLowerCase() + '.' + unique() + '@example.com',
            PersonMailingCountry = 'Spain',
            PersonBirthdate = birthdate,
            OwnerId = ownerId
        );
        insert a;
        return [SELECT Id, PersonContactId, FirstName, LastName, PersonEmail FROM Account WHERE Id = :a.Id];
    }

    public static Id externalProfileId(String preferredName) {
        List<Profile> profiles = [SELECT Id FROM Profile WHERE Name = :preferredName LIMIT 1];
        if (profiles.isEmpty()) {
            profiles = [
                SELECT Id
                FROM Profile
                WHERE UserType IN ('CspLitePortal', 'PowerCustomerSuccess', 'CustomerSuccess')
                ORDER BY UserType
                LIMIT 1
            ];
        }
        return profiles[0].Id;
    }

    public static User communityUser(Account personAccount, String profileName) {
        User u = new User(
            Alias = personAccount.FirstName.left(5).toLowerCase(),
            Email = personAccount.PersonEmail,
            EmailEncodingKey = 'UTF-8',
            FirstName = personAccount.FirstName,
            LastName = personAccount.LastName,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_GB',
            ProfileId = externalProfileId(profileName),
            TimeZoneSidKey = 'Europe/London',
            Username = personAccount.PersonEmail + '.lctest',
            ContactId = personAccount.PersonContactId
        );
        insert u;
        return u;
    }

    public static Connect_Ambassador__c ambassador(Id contactId) {
        Connect_Ambassador__c a = new Connect_Ambassador__c(
            Contact__c = contactId,
            Display_Name__c = 'Ada',
            Profile_Slug__c = AMBASSADOR_SLUG,
            Headline__c = 'Second-year Computer Science student',
            Bio__c = 'Ask me about the course and first-year halls.',
            Subject_Area__c = 'Computing',
            Study_Level__c = 'Undergraduate',
            Year_of_Study__c = 'Year 2',
            Home_Country__c = 'Nigeria',
            Home_Country_Code__c = 'NG',
            Interests__c = 'Gaming;Coding and tech',
            Languages__c = 'English;Yoruba',
            Status__c = 'Published',
            Available_For_Chat__c = true,
            Training_Completed__c = true,
            Last_Active__c = Datetime.now()
        );
        insert a;
        return a;
    }

    public static LC_Setting__mdt settings(String ownerUsername) {
        return new LC_Setting__mdt(
            DeveloperName = 'Default',
            Poll_Interval_Seconds__c = 5,
            Max_Messages_Per_Minute__c = 50,
            Max_New_Conversations_Per_Day__c = 10,
            Retention_Months__c = 24,
            Guidelines_Version__c = '1.0',
            Minimum_Age__c = 16,
            Record_Owner_Username__c = ownerUsername,
            Moderation_Queue__c = 'LC_Queue_That_Does_Not_Exist',
            Admissions_Queue__c = 'LC_Queue_That_Does_Not_Exist',
            Allowed_Link_Domains__c = 'launchededx.ac.uk'
        );
    }

    public static List<LC_Moderation_Rule__mdt> rules() {
        return new List<LC_Moderation_Rule__mdt>{
            new LC_Moderation_Rule__mdt(
                DeveloperName = 'Phone_Number',
                Pattern__c = '(\\+?\\d[\\d\\s\\-]{8,}\\d)',
                Reason__c = 'Contact details',
                Severity__c = 'Medium',
                Action__c = 'Hold',
                Applies_To__c = 'All',
                Message_To_Sender__c = 'Please do not share phone numbers.'
            ),
            new LC_Moderation_Rule__mdt(
                DeveloperName = 'Web_Link',
                Pattern__c = '(https?://|www\\.)',
                Reason__c = 'Contact details',
                Severity__c = 'Low',
                Action__c = 'Hold',
                Applies_To__c = 'All'
            ),
            new LC_Moderation_Rule__mdt(
                DeveloperName = 'Worry_Word',
                Pattern__c = '\\bunsafe\\b',
                Reason__c = 'Safeguarding keyword',
                Severity__c = 'High',
                Action__c = 'Flag only',
                Applies_To__c = 'Prospect'
            )
        };
    }
}
