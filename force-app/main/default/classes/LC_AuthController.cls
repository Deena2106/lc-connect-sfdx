/**
 * Launched Connect - passwordless login and self-registration for the LWR site.
 *
 * Step 1  startLogin(email)            -> existing user: sends a code (mode = 'login')
 *                                       -> new email:     mode = 'register'
 * Step 2a verifyLogin(...)              -> returns the URL that completes login
 * Step 2b startRegistration(...)        -> sends a code for a new account
 *         verifyRegistration(...)       -> creates the user (Person Account) and logs in
 *
 * Runs as the site guest user, so it must be without sharing to find users by email.
 * Prerequisites (Experience Workspaces > Administration > Login & Registration):
 *  - "Allow customers and partners to self-register" ON
 *  - Default profile = LC Prospect, Account left blank (creates a Person Account)
 *  - Verification by email enabled for the site
 */
public without sharing class LC_AuthController {
    @TestVisible
    private static final String USERNAME_SUFFIX = '.launchedconnect';
    private static final Pattern EMAIL_PATTERN = Pattern.compile('^[A-Za-z0-9._%+\\-\']+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}$');

    public class StartResult {
        @AuraEnabled public String mode; // login | register
        @AuraEnabled public String userId;
        @AuraEnabled public String identifier;
        @AuraEnabled public String email;
    }

    @AuraEnabled
    public static StartResult startLogin(String email) {
        String clean = normaliseEmail(email);
        StartResult result = new StartResult();
        result.email = clean;

        List<User> matches = findSiteUsers(clean);
        if (matches.isEmpty()) {
            result.mode = 'register';
            return result;
        }
        if (matches.size() > 1) {
            throw LC_Context.error('We could not sign you in with this email. Please contact the university.');
        }
        result.mode = 'login';
        result.userId = matches[0].Id;
        if (!Test.isRunningTest()) {
            result.identifier = System.UserManagement.initPasswordlessLogin(matches[0].Id, Auth.VerificationMethod.EMAIL);
        }
        return result;
    }

    @AuraEnabled
    public static String verifyLogin(String userId, String identifier, String code, String startUrl) {
        if (String.isBlank(userId) || String.isBlank(identifier) || String.isBlank(code)) {
            throw LC_Context.error('Please enter the 6-digit code from your email.');
        }
        Auth.VerificationResult res = System.UserManagement.verifyPasswordlessLogin(
            Id.valueOf(userId),
            Auth.VerificationMethod.EMAIL,
            identifier,
            code.trim(),
            safeStartUrl(startUrl)
        );
        return handle(res);
    }

    @AuraEnabled
    public static StartResult startRegistration(String firstName, String lastName, String email) {
        String clean = normaliseEmail(email);
        if (String.isBlank(firstName) || String.isBlank(lastName)) {
            throw LC_Context.error('Please enter your first and last name.');
        }
        if (!findSiteUsers(clean).isEmpty()) {
            throw LC_Context.error('You already have an account. Please log in instead.');
        }
        User u = new User(
            FirstName = firstName.trim().left(40),
            LastName = lastName.trim().left(80),
            Email = clean,
            Username = (clean + USERNAME_SUFFIX).left(80),
            CommunityNickname = nickname(firstName)
        );
        StartResult result = new StartResult();
        result.mode = 'register';
        result.email = clean;
        if (!Test.isRunningTest()) {
            result.identifier = System.UserManagement.initSelfRegistration(Auth.VerificationMethod.EMAIL, u);
        }
        return result;
    }

    @AuraEnabled
    public static String verifyRegistration(String identifier, String code, String startUrl) {
        if (String.isBlank(identifier) || String.isBlank(code)) {
            throw LC_Context.error('Please enter the 6-digit code from your email.');
        }
        Auth.VerificationResult res = System.UserManagement.verifySelfRegistration(
            Auth.VerificationMethod.EMAIL,
            identifier,
            code.trim(),
            safeStartUrl(startUrl)
        );
        return handle(res);
    }

    // ---------------------------------------------------------------- helpers

    private static String handle(Auth.VerificationResult res) {
        if (res != null && res.success && res.redirect != null) {
            return res.redirect.getUrl();
        }
        String message = (res == null || String.isBlank(res.message))
            ? 'That code did not work. Please check it and try again.'
            : res.message;
        throw LC_Context.error(message);
    }

    @TestVisible
    private static String normaliseEmail(String email) {
        String clean = email == null ? '' : email.trim().toLowerCase();
        if (!EMAIL_PATTERN.matcher(clean).matches()) {
            throw LC_Context.error('Please enter a valid email address.');
        }
        return clean;
    }

    private static List<User> findSiteUsers(String email) {
        List<User> users = [
            SELECT Id
            FROM User
            WHERE Email = :email AND IsActive = TRUE AND ContactId != NULL
            LIMIT 5
        ];
        Id networkId = Network.getNetworkId();
        if (networkId == null || users.isEmpty()) {
            return users;
        }
        Set<Id> ids = new Map<Id, User>(users).keySet();
        List<User> members = new List<User>();
        for (NetworkMember m : [SELECT MemberId FROM NetworkMember WHERE NetworkId = :networkId AND MemberId IN :ids]) {
            members.add(new User(Id = m.MemberId));
        }
        return members;
    }

    /** Only allow relative, same-site paths as the post-login destination. */
    @TestVisible
    private static String safeStartUrl(String startUrl) {
        if (String.isBlank(startUrl) || !startUrl.startsWith('/') || startUrl.startsWith('//') || startUrl.contains('\\')) {
            return '/';
        }
        return startUrl;
    }

    private static String nickname(String firstName) {
        String base = firstName == null ? 'user' : firstName.replaceAll('[^A-Za-z0-9]', '').toLowerCase();
        if (String.isBlank(base)) {
            base = 'user';
        }
        return (base.left(20) + String.valueOf(Crypto.getRandomInteger()).replace('-', '')).left(40);
    }
}
