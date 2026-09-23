/**
 * Launched Connect - public ambassador directory and profiles.
 * Used by guests and logged-in users on the LWR site.
 *
 * Runs without sharing on purpose: it only ever returns Published, available
 * ambassadors and only the public fields listed in AmbassadorCard. No other
 * data is exposed. Keep the guest sharing rule in place as defence in depth.
 */
public without sharing class LC_DirectoryController {
    private static final Integer ONLINE_MINUTES = 15;
    private static final Integer MAX_ROWS = 1000;

    public class AmbassadorCard {
        @AuraEnabled public Id id;
        @AuraEnabled public String slug;
        @AuraEnabled public String displayName;
        @AuraEnabled public String headline;
        @AuraEnabled public String bio;
        @AuraEnabled public String programme;
        @AuraEnabled public String subjectArea;
        @AuraEnabled public String studyLevel;
        @AuraEnabled public String yearOfStudy;
        @AuraEnabled public String homeCountry;
        @AuraEnabled public String homeCountryCode;
        @AuraEnabled public String homeCity;
        @AuraEnabled public String photoUrl;
        @AuraEnabled public Boolean livedInHalls;
        @AuraEnabled public Boolean online;
        @AuraEnabled public Integer avgResponseMinutes;
        @AuraEnabled public Integer conversations;
        @AuraEnabled public List<String> interests;
        @AuraEnabled public List<String> languages;
    }

    public class DirectoryResult {
        @AuraEnabled public List<AmbassadorCard> ambassadors = new List<AmbassadorCard>();
        @AuraEnabled public Integer total = 0;
        @AuraEnabled public Integer onlineCount = 0;
        @AuraEnabled public Boolean hasMore = false;
    }

    public class Option {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public Option(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class FilterOptions {
        @AuraEnabled public List<Option> subjects = new List<Option>();
        @AuraEnabled public List<Option> studyLevels = new List<Option>();
        @AuraEnabled public List<Option> countries = new List<Option>();
        @AuraEnabled public List<Option> languages = new List<Option>();
    }

    @AuraEnabled(cacheable=true)
    public static FilterOptions getFilterOptions() {
        FilterOptions out = new FilterOptions();
        Set<String> subjects = new Set<String>();
        Set<String> countries = new Set<String>();
        for (Connect_Ambassador__c a : publishedAmbassadors()) {
            if (String.isNotBlank(a.Subject_Area__c)) {
                subjects.add(a.Subject_Area__c);
            }
            if (String.isNotBlank(a.Home_Country__c)) {
                countries.add(a.Home_Country__c);
            }
        }
        out.subjects = toOptions(subjects);
        out.countries = toOptions(countries);
        for (Schema.PicklistEntry e : Connect_Ambassador__c.Study_Level__c.getDescribe().getPicklistValues()) {
            if (e.isActive()) {
                out.studyLevels.add(new Option(e.getLabel(), e.getValue()));
            }
        }
        for (Schema.PicklistEntry e : Connect_Ambassador__c.Languages__c.getDescribe().getPicklistValues()) {
            if (e.isActive()) {
                out.languages.add(new Option(e.getLabel(), e.getValue()));
            }
        }
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static DirectoryResult searchAmbassadors(
        String searchTerm,
        String subject,
        String studyLevel,
        String country,
        String language,
        Integer pageSize,
        Integer pageNumber
    ) {
        Integer size = (pageSize == null || pageSize < 1 || pageSize > 50) ? 12 : pageSize;
        Integer page = (pageNumber == null || pageNumber < 1) ? 1 : pageNumber;
        String term = String.isBlank(searchTerm) ? null : searchTerm.trim().toLowerCase();

        List<AmbassadorCard> matches = new List<AmbassadorCard>();
        DirectoryResult result = new DirectoryResult();
        for (Connect_Ambassador__c a : publishedAmbassadors()) {
            if (String.isNotBlank(subject) && a.Subject_Area__c != subject) {
                continue;
            }
            if (String.isNotBlank(studyLevel) && a.Study_Level__c != studyLevel) {
                continue;
            }
            if (String.isNotBlank(country) && a.Home_Country__c != country) {
                continue;
            }
            if (String.isNotBlank(language) && !splitMulti(a.Languages__c).contains(language)) {
                continue;
            }
            if (term != null && !matchesTerm(a, term)) {
                continue;
            }
            AmbassadorCard card = toCard(a, false);
            if (card.online) {
                result.onlineCount++;
            }
            matches.add(card);
        }
        result.total = matches.size();
        Integer startIdx = (page - 1) * size;
        for (Integer i = startIdx; i < Math.min(startIdx + size, matches.size()); i++) {
            result.ambassadors.add(matches[i]);
        }
        result.hasMore = matches.size() > startIdx + size;
        return result;
    }

    /** Accepts a profile slug or a record Id. Returns null if not published. */
    @AuraEnabled(cacheable=true)
    public static AmbassadorCard getAmbassador(String slugOrId) {
        Connect_Ambassador__c a = findPublished(slugOrId);
        return a == null ? null : toCard(a, true);
    }

    // ---------------------------------------------------------------- helpers

    public static Connect_Ambassador__c findPublished(String slugOrId) {
        if (String.isBlank(slugOrId)) {
            return null;
        }
        String key = slugOrId.trim();
        Id recordId = null;
        if (key.length() == 15 || key.length() == 18) {
            try {
                recordId = Id.valueOf(key);
            } catch (StringException e) {
                recordId = null;
            }
        }
        List<Connect_Ambassador__c> rows = [
            SELECT
                Id, Profile_Slug__c, Display_Name__c, Headline__c, Bio__c, Learning_Program__r.Name,
                Subject_Area__c, Study_Level__c, Year_of_Study__c, Home_Country__c, Home_Country_Code__c,
                Home_City__c, Photo_Url__c, Lived_In_Halls__c, Last_Active__c, Avg_First_Response_Minutes__c,
                Conversations_Count__c, Interests__c, Languages__c, Contact__c
            FROM Connect_Ambassador__c
            WHERE
                (Profile_Slug__c = :key OR Id = :recordId)
                AND Status__c = 'Published'
                AND Available_For_Chat__c = TRUE
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static List<Connect_Ambassador__c> publishedAmbassadors() {
        return [
            SELECT
                Id, Profile_Slug__c, Display_Name__c, Headline__c, Learning_Program__r.Name, Subject_Area__c,
                Study_Level__c, Year_of_Study__c, Home_Country__c, Home_Country_Code__c, Home_City__c,
                Photo_Url__c, Lived_In_Halls__c, Last_Active__c, Avg_First_Response_Minutes__c,
                Conversations_Count__c, Interests__c, Languages__c
            FROM Connect_Ambassador__c
            WHERE Status__c = 'Published' AND Available_For_Chat__c = TRUE
            ORDER BY Last_Active__c DESC NULLS LAST, Display_Name__c
            LIMIT :MAX_ROWS
        ];
    }

    private static Boolean matchesTerm(Connect_Ambassador__c a, String term) {
        List<String> haystack = new List<String>{
            a.Display_Name__c,
            a.Headline__c,
            a.Subject_Area__c,
            a.Home_Country__c,
            a.Home_City__c,
            a.Learning_Program__r?.Name,
            a.Interests__c,
            a.Languages__c
        };
        for (String s : haystack) {
            if (s != null && s.toLowerCase().contains(term)) {
                return true;
            }
        }
        return false;
    }

    private static AmbassadorCard toCard(Connect_Ambassador__c a, Boolean includeBio) {
        AmbassadorCard c = new AmbassadorCard();
        c.id = a.Id;
        c.slug = String.isBlank(a.Profile_Slug__c) ? String.valueOf(a.Id) : a.Profile_Slug__c;
        c.displayName = a.Display_Name__c;
        c.headline = a.Headline__c;
        c.bio = includeBio ? a.Bio__c : null;
        c.programme = a.Learning_Program__r?.Name;
        c.subjectArea = a.Subject_Area__c;
        c.studyLevel = a.Study_Level__c;
        c.yearOfStudy = a.Year_of_Study__c;
        c.homeCountry = a.Home_Country__c;
        c.homeCountryCode = a.Home_Country_Code__c;
        c.homeCity = a.Home_City__c;
        c.photoUrl = a.Photo_Url__c;
        c.livedInHalls = a.Lived_In_Halls__c;
        c.online = a.Last_Active__c != null && a.Last_Active__c > Datetime.now().addMinutes(-ONLINE_MINUTES);
        c.avgResponseMinutes = a.Avg_First_Response_Minutes__c == null ? null : a.Avg_First_Response_Minutes__c.intValue();
        c.conversations = a.Conversations_Count__c == null ? 0 : a.Conversations_Count__c.intValue();
        c.interests = splitMulti(a.Interests__c);
        c.languages = splitMulti(a.Languages__c);
        return c;
    }

    private static List<String> splitMulti(String value) {
        return String.isBlank(value) ? new List<String>() : value.split(';');
    }

    private static List<Option> toOptions(Set<String> values) {
        List<String> sorted = new List<String>(values);
        sorted.sort();
        List<Option> out = new List<Option>();
        for (String s : sorted) {
            out.add(new Option(s, s));
        }
        return out;
    }
}
