export type AdministratorQuoteContext =
  | 'match_start'
  | 'admin_sweep'
  | 'admin_clear_win'
  | 'admin_close_win'
  | 'player_sweep'
  | 'player_clear_win'
  | 'player_close_win'
  | 'draw'

export const ADMINISTRATOR_QUOTES: Readonly<Record<AdministratorQuoteContext, readonly string[]>> = {
  match_start: [
    "No challengers? Then I'll handle this myself.",
    "The Arena is quiet. I suppose you're mine.",
    "Let's see what your record is really worth.",
    'You waited long enough. Fight me.',
    "Matchmaking failed you. I won't.",
    "The queue was empty. The Arena isn't.",
    'No opponent answered. I did.',
    "Let's make the wait worthwhile.",
  ],
  admin_sweep: [
    'You entered the Arena. You were not ready for it.',
    'Three rounds. That was all I needed.',
    'I expected more resistance.',
    "I'll mark that one as efficient.",
    'That was less of a battle than I expected.',
  ],
  admin_clear_win: [
    'Better. You made me work for one of them.',
    'A little resistance. I appreciate that.',
    'You found an opening. Just not enough of them.',
    'Progress, perhaps. Victory, no.',
  ],
  admin_close_win: [
    "That was closer than I'd like to admit.",
    "One round separated us. Don't get comfortable.",
    'You nearly took that from me.',
    'A respectable loss is still a loss.',
    'You made that inconvenient.',
  ],
  player_sweep: [
    "...I'll be reviewing that match.",
    'That result requires recalibration.',
    'You have my attention now.',
    'Three rounds. None of them mine. Noted.',
    "I'll remember that.",
  ],
  player_clear_win: [
    'Well played. I clearly need recalibration.',
    'You earned that one.',
    'The record has been updated. Unfortunately.',
    'Enjoy it. You were the better fighter this time.',
  ],
  player_close_win: [
    'You barely got away with that.',
    'One round separated us. Remember that.',
    'Fine. That one belongs to you.',
    "I'll update the record. Not the grudge.",
    "You survived the last exchange. That's enough.",
  ],
  draw: [
    'Apparently neither of us deserves the point.',
    'An unresolved outcome. Irritating.',
    "We'll settle that another time.",
    'No winner. I dislike unfinished records.',
  ],
}
