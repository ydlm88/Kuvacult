// Blackjack tiebreaker — pure game logic (no Flutter). Port of reference/Blackjack Table v2.dc.html.
//
// RULES (exactly as designed):
//  • Every player in the round gets 2 cards. House gets 2; the second is face-down.
//  • Players act in seat order. Seat 0 is the local user (Hit / Stand). Other seats are
//    remote players in production — in the demo they auto-play: hit below 17, else stand.
//    A hand that reaches 21 or busts ends that player's turn automatically.
//  • After the last player the House flips and draws to 17 (stands on all 17s).
//  • Highest non-bust hand keeps its film ONLY if it beats the House (or the House busts).
//      – exactly one such player → they win.
//      – tie between several → "Deal again".
//      – nobody beats the House → "Deal again".
//  • CUT RULE: if the round had MORE THAN 3 players, Deal again only re-deals the players
//    tied for the top non-bust hand. Everyone else is OUT (tile stays, dimmed, "OUT").
//    If everyone busted, nobody is cut.
//  • If the cut would leave exactly ONE player, that player wins on the spot (even if the
//    House beat them) — no extra round.
//  • 3 or fewer players: Deal again re-deals the same roster, nobody is cut.
//  • "Clear" restarts the whole game with everyone back in.

import 'dart:math';

enum Suit { spade, heart, diamond, club }

class PlayingCard {
  const PlayingCard(this.rank, this.suit);
  final String rank; // A 2–10 J Q K
  final Suit suit;
  bool get red => suit == Suit.heart || suit == Suit.diamond;
}

const ranks = ['A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K'];

int handValue(List<PlayingCard> h) {
  var t = 0, aces = 0;
  for (final c in h) {
    if (c.rank == 'A') {
      aces++;
      t += 11;
    } else {
      t += const ['J', 'Q', 'K'].contains(c.rank) ? 10 : int.parse(c.rank);
    }
  }
  while (t > 21 && aces > 0) {
    t -= 10;
    aces--;
  }
  return t;
}

enum Phase { play, house, done }

class Player {
  const Player(this.name, this.film);
  final String name, film;
}

class Outcome {
  const Outcome({required this.winners, required this.advancing, required this.status, required this.lastOneStanding});
  final List<int> winners; // seat indices highlighted gold
  final List<int> advancing; // roster for Deal again
  final String status;
  final bool lastOneStanding;
  bool get needsDealAgain => winners.length != 1;
}

class TiebreakerGame {
  TiebreakerGame(this.players, {Random? rng}) : _rng = rng ?? Random() {
    _deal(List.generate(players.length, (i) => i), 1);
  }

  final List<Player> players;
  final Random _rng;

  late List<int> roster; // seats still in the game
  late int round;
  late List<PlayingCard> deck;
  late List<List<PlayingCard>> hands; // indexed by seat; empty for OUT seats
  late List<PlayingCard> house;
  int turn = 0; // index into roster
  Phase phase = Phase.play;
  bool reveal = false;

  int get n => players.length;
  int? get currentSeat => phase == Phase.play && turn < roster.length ? roster[turn] : null;
  bool get isUsersTurn => currentSeat == 0;
  bool isOut(int seat) => !roster.contains(seat);

  void _deal(List<int> r, int rnd) {
    roster = List.of(r);
    round = rnd;
    deck = [for (final s in Suit.values) for (final k in ranks) PlayingCard(k, s)]..shuffle(_rng);
    hands = List.generate(n, (i) => roster.contains(i) ? [deck.removeLast(), deck.removeLast()] : <PlayingCard>[]);
    house = [deck.removeLast(), deck.removeLast()];
    turn = 0;
    phase = Phase.play;
    reveal = false;
  }

  void _advance() {
    turn++;
    if (turn >= roster.length) {
      phase = Phase.house;
      reveal = true;
    }
  }

  void hit(int seat) {
    if (currentSeat != seat) return;
    hands[seat].add(deck.removeLast());
    if (handValue(hands[seat]) >= 21) _advance();
  }

  void stand(int seat) {
    if (currentSeat != seat) return;
    _advance();
  }

  /// Demo AI for a non-user seat. Returns true if it hit.
  bool autoPlay(int seat) {
    if (handValue(hands[seat]) < 17) {
      hit(seat);
      return true;
    }
    stand(seat);
    return false;
  }

  /// One House step: draw if < 17, otherwise finish. Call every 800ms while phase == house.
  void houseStep() {
    if (phase != Phase.house) return;
    if (handValue(house) < 17) {
      house.add(deck.removeLast());
    } else {
      phase = Phase.done;
    }
  }

  Outcome outcome() {
    final houseV = handValue(house), houseBust = houseV > 21;
    final live = [for (final i in roster) if (handValue(hands[i]) <= 21) i];
    final best = live.isEmpty ? 0 : live.map((i) => handValue(hands[i])).reduce(max);
    final done = phase == Phase.done;
    final beats = best > 0 && (houseBust || best > houseV);
    var winners = done && beats ? [for (final i in live) if (handValue(hands[i]) == best) i] : <int>[];
    final cut = roster.length > 3;
    final top = live.isEmpty ? List.of(roster) : [for (final i in live) if (handValue(hands[i]) == best) i];
    final advancing = cut ? top : List.of(roster);

    String names(List<int> ids) => ids.map((i) => players[i].name).join(' & ');
    final tail = cut && advancing.length < roster.length
        ? ' ${names(advancing)} go${advancing.length == 1 ? 'es' : ''} through.'
        : '';
    final lastOne = done && winners.length != 1 && cut && advancing.length == 1;
    if (lastOne) winners = [advancing.first];

    String status;
    if (phase == Phase.play) {
      status = isUsersTurn ? 'Your turn — hit or stand' : "${players[currentSeat!].name}'s turn…";
    } else if (phase == Phase.house) {
      status = 'House flips…';
    } else if (lastOne) {
      status = '${players[winners.first].name} has the top hand. ${players[winners.first].film} survives';
    } else if (winners.length == 1) {
      status = '${players[winners.first].name} beats the House — ${players[winners.first].film} survives';
    } else if (winners.length > 1) {
      status = '${names(winners)} tie on $best.${tail.isEmpty ? ' Deal again to settle it.' : tail}';
    } else {
      status = (houseBust ? 'Everyone busted.' : "Nobody beat the House's $houseV.") + (tail.isEmpty ? ' Deal again.' : tail);
    }
    return Outcome(winners: winners, advancing: advancing, status: status, lastOneStanding: lastOne);
  }

  void dealAgain() {
    final o = outcome();
    _deal(o.advancing, round + 1);
  }

  void clear() => _deal(List.generate(n, (i) => i), 1);
}
