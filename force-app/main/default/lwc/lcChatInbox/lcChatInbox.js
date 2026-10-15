import { LightningElement, api } from 'lwc';
import { avatarStyle, initials, relativeTime } from 'c/lcUtils';

/**
 * Launched Connect - list of conversations (child component).
 * Fires "select" with detail { id }.
 */
export default class LcChatInbox extends LightningElement {
    @api heading = 'My chats';
    @api conversations = [];
    @api selectedId;
    @api findUrl;
    /** 'prospect' or 'ambassador' - ambassadors see waiting-time badges */
    @api viewerRole = 'prospect';
    @api emptyText = 'No chats yet. Find an ambassador to ask your first question.';

    get count() {
        return (this.conversations || []).length;
    }

    get isEmpty() {
        return this.count === 0;
    }

    get items() {
        return (this.conversations || []).map((c) => {
            const selected = c.id === this.selectedId;
            const waiting = Number(c.waitingHours || 0);
            const isAmb = this.viewerRole === 'ambassador';
            let badge = '';
            let badgeClass = 'inbox__badge';
            if (isAmb) {
                if (c.status === 'Closed') {
                    badge = 'Done';
                    badgeClass += ' inbox__badge_done';
                } else if (c.lastMessageBy === 'Prospect') {
                    badge = waiting < 1 ? '<1h' : `${Math.round(waiting)}h`;
                    badgeClass += waiting >= 24 ? ' inbox__badge_late' : ' inbox__badge_wait';
                }
            } else if (c.status === 'Paused' || c.status === 'Under Review') {
                badge = 'Paused';
                badgeClass += ' inbox__badge_wait';
            }
            const mine = (isAmb && c.lastMessageBy === 'Ambassador') || (!isAmb && c.lastMessageBy === 'Prospect');
            return {
                ...c,
                cssClass: selected ? 'inbox__item inbox__item_on' : 'inbox__item',
                ariaCurrent: selected ? 'true' : 'false',
                avatarStyle: avatarStyle(c.counterpartName || c.name, 42),
                initials: initials(c.counterpartName),
                when: relativeTime(c.lastMessageAt),
                subtitle: c.counterpartSubtitle || '',
                preview: c.lastMessagePreview ? `${mine ? 'You: ' : ''}${c.lastMessagePreview}` : 'No messages yet',
                badge,
                badgeClass,
                showBadge: Boolean(badge)
            };
        });
    }

    handleSelect(event) {
        this.dispatchEvent(new CustomEvent('select', { detail: { id: event.currentTarget.dataset.id } }));
    }
}