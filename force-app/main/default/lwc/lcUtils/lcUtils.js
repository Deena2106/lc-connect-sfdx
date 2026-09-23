/**
 * Launched Connect - shared helpers for the LWR site components.
 */
import basePath from '@salesforce/community/basePath';

// Page URLs on the LWR site (relative to the site base path).
// Keep in step with the URL set on each page in Experience Builder.
export const ROUTES = {
    home: '/',
    profile: '/ambassador',
    login: '/login',
    completeProfile: '/complete-profile',
    messages: '/messages',
    inbox: '/inbox',
    myProfile: '/my-profile',
    guidelines: '/guidelines'
};

const PALETTE = ['#7c3aed', '#0e7490', '#b45309', '#be185d', '#15803d', '#0369a1', '#9333ea', '#c2410c', '#4d7c0f', '#1d4ed8'];

/** Full site URL for a route, with optional query parameters. */
export function siteUrl(route, params) {
    const base = (basePath || '').replace(/\/$/, '');
    let path = route === '/' ? base + '/' : base + route;
    if (params) {
        const query = Object.keys(params)
            .filter((k) => params[k] !== undefined && params[k] !== null && params[k] !== '')
            .map((k) => `${encodeURIComponent(k)}=${encodeURIComponent(params[k])}`)
            .join('&');
        if (query) {
            path += `?${query}`;
        }
    }
    return path;
}

/** Reads a query-string parameter from the current URL. */
export function queryParam(name) {
    try {
        return new URLSearchParams(window.location.search).get(name);
    } catch (e) {
        return null;
    }
}

/** Sends the visitor to start a chat, via login if they are a guest. */
export function goToChat(ambassadorSlug, origin, isGuest) {
    const chatUrl = siteUrl(ROUTES.messages, { ambassador: ambassadorSlug, origin });
    if (isGuest) {
        const next = siteUrl(ROUTES.completeProfile, { ambassador: ambassadorSlug, origin });
        window.location.assign(siteUrl(ROUTES.login, { startURL: next, ambassador: ambassadorSlug }));
    } else {
        window.location.assign(chatUrl);
    }
}

/** Stores UTM values so they survive the login round trip. */
export function rememberUtm() {
    try {
        const params = new URLSearchParams(window.location.search);
        const utm = {};
        ['utm_source', 'utm_medium', 'utm_campaign'].forEach((k) => {
            if (params.get(k)) {
                utm[k] = params.get(k);
            }
        });
        if (Object.keys(utm).length) {
            window.sessionStorage.setItem('lc_utm', JSON.stringify(utm));
        }
    } catch (e) {
        // Storage can be unavailable (private browsing); UTM capture is optional.
    }
}

export function readUtm() {
    try {
        return JSON.parse(window.sessionStorage.getItem('lc_utm') || '{}');
    } catch (e) {
        return {};
    }
}

export function initials(name) {
    if (!name) {
        return '?';
    }
    const parts = String(name).trim().split(/\s+/);
    const first = parts[0] ? parts[0][0] : '';
    const second = parts.length > 1 ? parts[parts.length - 1][0] : parts[0] && parts[0][1] ? parts[0][1] : '';
    return (first + second).toUpperCase();
}

export function avatarColour(seed) {
    const text = String(seed || '');
    let hash = 0;
    for (let i = 0; i < text.length; i++) {
        hash = (hash * 31 + text.charCodeAt(i)) % 100000;
    }
    return PALETTE[hash % PALETTE.length];
}

export function avatarStyle(seed, size) {
    const px = size || 48;
    return `background:${avatarColour(seed)};width:${px}px;height:${px}px;font-size:${Math.round(px / 2.8)}px;`;
}

export function formatTime(value) {
    if (!value) {
        return '';
    }
    const d = new Date(value);
    const now = new Date();
    const sameDay = d.toDateString() === now.toDateString();
    const opts = sameDay ? { hour: '2-digit', minute: '2-digit' } : { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' };
    return new Intl.DateTimeFormat(undefined, opts).format(d);
}

export function relativeTime(value) {
    if (!value) {
        return '';
    }
    const mins = Math.round((Date.now() - new Date(value).getTime()) / 60000);
    if (mins < 1) {
        return 'now';
    }
    if (mins < 60) {
        return `${mins}m`;
    }
    const hours = Math.round(mins / 60);
    if (hours < 24) {
        return `${hours}h`;
    }
    return `${Math.round(hours / 24)}d`;
}

export function replyTimeLabel(minutes) {
    if (minutes === null || minutes === undefined) {
        return null;
    }
    if (minutes < 60) {
        return 'Usually replies within an hour';
    }
    const hours = Math.ceil(minutes / 60);
    return hours <= 24 ? `Usually replies within ${hours} hours` : 'Usually replies within a few days';
}

export function uuid() {
    if (window.crypto && window.crypto.randomUUID) {
        return window.crypto.randomUUID();
    }
    return 'lc-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 10);
}

/** Turns an Apex / LDS error into readable text. */
export function reduceError(error) {
    if (!error) {
        return 'Something went wrong. Please try again.';
    }
    if (Array.isArray(error.body)) {
        return error.body.map((e) => e.message).join(', ');
    }
    if (error.body && typeof error.body.message === 'string') {
        return error.body.message;
    }
    if (typeof error.message === 'string') {
        return error.message;
    }
    return 'Something went wrong. Please try again.';
}

/** Countries for the "Country of residence" picklist (United Kingdom first). */
export const COUNTRIES = [
    'United Kingdom', 'Afghanistan', 'Albania', 'Algeria', 'Andorra', 'Angola', 'Antigua and Barbuda', 'Argentina', 'Armenia', 'Australia',
    'Austria', 'Azerbaijan', 'Bahamas', 'Bahrain', 'Bangladesh', 'Barbados', 'Belarus', 'Belgium', 'Belize', 'Benin', 'Bhutan', 'Bolivia',
    'Bosnia and Herzegovina', 'Botswana', 'Brazil', 'Brunei', 'Bulgaria', 'Burkina Faso', 'Burundi', 'Cambodia', 'Cameroon', 'Canada',
    'Cape Verde', 'Central African Republic', 'Chad', 'Chile', 'China', 'Colombia', 'Comoros', 'Congo', 'Costa Rica', "Côte d'Ivoire",
    'Croatia', 'Cuba', 'Cyprus', 'Czechia', 'Democratic Republic of the Congo', 'Denmark', 'Djibouti', 'Dominica', 'Dominican Republic',
    'Ecuador', 'Egypt', 'El Salvador', 'Equatorial Guinea', 'Eritrea', 'Estonia', 'Eswatini', 'Ethiopia', 'Fiji', 'Finland', 'France',
    'Gabon', 'Gambia', 'Georgia', 'Germany', 'Ghana', 'Greece', 'Grenada', 'Guatemala', 'Guinea', 'Guinea-Bissau', 'Guyana', 'Haiti',
    'Honduras', 'Hong Kong', 'Hungary', 'Iceland', 'India', 'Indonesia', 'Iran', 'Iraq', 'Ireland', 'Israel', 'Italy', 'Jamaica', 'Japan',
    'Jordan', 'Kazakhstan', 'Kenya', 'Kiribati', 'Kosovo', 'Kuwait', 'Kyrgyzstan', 'Laos', 'Latvia', 'Lebanon', 'Lesotho', 'Liberia',
    'Libya', 'Liechtenstein', 'Lithuania', 'Luxembourg', 'Macao', 'Madagascar', 'Malawi', 'Malaysia', 'Maldives', 'Mali', 'Malta',
    'Marshall Islands', 'Mauritania', 'Mauritius', 'Mexico', 'Micronesia', 'Moldova', 'Monaco', 'Mongolia', 'Montenegro', 'Morocco',
    'Mozambique', 'Myanmar', 'Namibia', 'Nauru', 'Nepal', 'Netherlands', 'New Zealand', 'Nicaragua', 'Niger', 'Nigeria', 'North Korea',
    'North Macedonia', 'Norway', 'Oman', 'Pakistan', 'Palau', 'Palestine', 'Panama', 'Papua New Guinea', 'Paraguay', 'Peru', 'Philippines',
    'Poland', 'Portugal', 'Qatar', 'Romania', 'Russia', 'Rwanda', 'Saint Kitts and Nevis', 'Saint Lucia', 'Saint Vincent and the Grenadines',
    'Samoa', 'San Marino', 'São Tomé and Príncipe', 'Saudi Arabia', 'Senegal', 'Serbia', 'Seychelles', 'Sierra Leone', 'Singapore',
    'Slovakia', 'Slovenia', 'Solomon Islands', 'Somalia', 'South Africa', 'South Korea', 'South Sudan', 'Spain', 'Sri Lanka', 'Sudan',
    'Suriname', 'Sweden', 'Switzerland', 'Syria', 'Taiwan', 'Tajikistan', 'Tanzania', 'Thailand', 'Timor-Leste', 'Togo', 'Tonga',
    'Trinidad and Tobago', 'Tunisia', 'Turkey', 'Turkmenistan', 'Tuvalu', 'Uganda', 'Ukraine', 'United Arab Emirates', 'United States',
    'Uruguay', 'Uzbekistan', 'Vanuatu', 'Vatican City', 'Venezuela', 'Vietnam', 'Yemen', 'Zambia', 'Zimbabwe', 'Other'
].map((c) => ({ label: c, value: c }));
