// What the home page shows, as returned by GET /users/me/home.
// [HomeData.mock] is sample data for dev sessions without a server token.

enum BillStage {
  pickItems('Pick your items', 'pick_items'),
  waitingOnHost('Waiting on host', 'waiting_on_host'),
  charging('Charging cards', 'charging'),
  paid('Paid', 'paid');

  const BillStage(this.label, this.apiName);
  final String label;
  final String apiName;

  static BillStage fromApi(Object? name) => values.firstWhere(
    (stage) => stage.apiName == name,
    orElse: () => waitingOnHost,
  );
}

/// A bill in one of your groups that isn't finished yet.
class HomeBill {
  const HomeBill({
    required this.groupName,
    required this.title,
    required this.stage,
    required this.amountCents,
    required this.people,
    this.isHost = false,
  });

  final String groupName;
  final String title;
  final BillStage stage;

  /// Your share if you're a member; what you're collecting if you're hosting.
  final int amountCents;
  final int people;
  final bool isHost;

  factory HomeBill.fromJson(Map<String, dynamic> json) => HomeBill(
    groupName: json['groupName'] as String? ?? '',
    title: json['title'] as String? ?? '',
    stage: BillStage.fromApi(json['stage']),
    amountCents: json['amountCents'] as int? ?? 0,
    people: json['people'] as int? ?? 0,
    isHost: json['isHost'] == true,
  );
}

enum ActivityKind {
  youPaid('you_paid'),
  paidYou('paid_you'),
  waived('waived'),
  joined('joined');

  const ActivityKind(this.apiName);
  final String apiName;

  static ActivityKind? fromApi(Object? name) {
    for (final kind in values) {
      if (kind.apiName == name) return kind;
    }
    return null;
  }
}

class HomeActivity {
  const HomeActivity({
    required this.kind,
    required this.who,
    required this.groupName,
    required this.when,
    this.amountCents = 0,
  });

  final ActivityKind kind;
  final String who;
  final String groupName;
  final DateTime when;
  final int amountCents;

  /// Null for kinds this version of the app doesn't know how to show.
  static HomeActivity? fromJson(Map<String, dynamic> json) {
    final kind = ActivityKind.fromApi(json['kind']);
    final when = DateTime.tryParse(json['at'] as String? ?? '');
    if (kind == null || when == null) return null;
    return HomeActivity(
      kind: kind,
      who: json['who'] as String? ?? '',
      groupName: json['groupName'] as String? ?? '',
      when: when.toLocal(),
      amountCents: json['amountCents'] as int? ?? 0,
    );
  }
}

class HomeData {
  const HomeData({
    required this.bills,
    required this.activity,
    this.isMock = false,
  });

  final List<HomeBill> bills;
  final List<HomeActivity> activity;
  final bool isMock;

  factory HomeData.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> rows(String key) => [
      for (final row in json[key] as List? ?? const [])
        if (row is Map<String, dynamic>) row,
    ];
    return HomeData(
      bills: rows('bills').map(HomeBill.fromJson).toList(),
      activity: rows('activity').map(HomeActivity.fromJson).nonNulls.toList(),
    );
  }

  /// Your share of bills you haven't paid yet.
  int get youOweCents => bills
      .where((b) => !b.isHost && b.stage != BillStage.paid)
      .fold(0, (sum, b) => sum + b.amountCents);

  /// Still coming to you from bills you're hosting.
  int get owedToYouCents => bills
      .where((b) => b.isHost && b.stage != BillStage.paid)
      .fold(0, (sum, b) => sum + b.amountCents);

  static HomeData mock({DateTime? now}) {
    final today = now ?? DateTime.now();
    DateTime ago({int days = 0, int hours = 0}) =>
        today.subtract(Duration(days: days, hours: hours));

    return HomeData(
      isMock: true,
      bills: const [
        HomeBill(
          groupName: 'Friday Dinner',
          title: 'The Tack Room',
          stage: BillStage.pickItems,
          amountCents: 3795,
          people: 4,
        ),
        HomeBill(
          groupName: 'Roommates',
          title: 'Costco run',
          stage: BillStage.charging,
          amountCents: 8640,
          people: 3,
          isHost: true,
        ),
        HomeBill(
          groupName: 'Ski Trip',
          title: 'Cabin groceries',
          stage: BillStage.waitingOnHost,
          amountCents: 2210,
          people: 6,
        ),
      ],
      activity: [
        HomeActivity(
          kind: ActivityKind.paidYou,
          who: 'bob',
          groupName: 'Roommates',
          amountCents: 4320,
          when: ago(hours: 2),
        ),
        HomeActivity(
          kind: ActivityKind.youPaid,
          who: 'alice',
          groupName: 'Brunch Club',
          amountCents: 2450,
          when: ago(days: 1),
        ),
        HomeActivity(
          kind: ActivityKind.waived,
          who: 'maya',
          groupName: 'Ski Trip',
          amountCents: 450,
          when: ago(days: 2),
        ),
        HomeActivity(
          kind: ActivityKind.joined,
          who: 'jordan',
          groupName: 'Friday Dinner',
          when: ago(days: 4),
        ),
        HomeActivity(
          kind: ActivityKind.youPaid,
          who: 'maya',
          groupName: 'Ski Trip',
          amountCents: 6125,
          when: ago(days: 6),
        ),
      ],
    );
  }
}
