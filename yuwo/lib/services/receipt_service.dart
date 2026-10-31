import '../splits/split_model.dart';
import 'auth_service.dart';

/// What was read from a receipt, for the host to check before starting the bill.
class ReceiptDraft {
  const ReceiptDraft({
    required this.items,
    this.merchantName,
    this.receiptDate,
    this.taxCents,
    this.tipCents,
    this.totalCents,
  });

  factory ReceiptDraft.fromJson(Map<String, dynamic> json) => ReceiptDraft(
    merchantName: json['merchantName'] as String?,
    receiptDate: json['receiptDate'] as String?,
    items: [
      for (final item
          in json['items'] is List ? json['items'] as List : const [])
        if (item is Map<String, dynamic>)
          NewBillItem(
            name: item['name'] as String,
            quantity: item['quantity'] as int,
            unitPriceCents: item['unitPriceCents'] as int,
          ),
    ],
    taxCents: json['taxCents'] as int?,
    tipCents: json['tipCents'] as int?,
    totalCents: json['totalCents'] as int?,
  );

  final String? merchantName;

  /// YYYY-MM-DD.
  final String? receiptDate;
  final List<NewBillItem> items;
  final int? taxCents;
  final int? tipCents;

  /// The receipt's printed total, to check the items against.
  final int? totalCents;
}

class ReceiptUpload {
  const ReceiptUpload({required this.receiptId, this.draft, this.scanError});

  final int receiptId;
  final ReceiptDraft? draft;

  /// Why nothing (or not everything) could be read; the photo is still saved.
  final String? scanError;
}

/// Receipt photos: read into a draft bill, then attached to the bill so the
/// group can see them.
class ReceiptService {
  const ReceiptService(this._auth);

  final AuthService _auth;

  /// Reading can take up to a minute on a long receipt.
  static const scanTimeout = Duration(seconds: 100);

  Future<ReceiptUpload> upload(
    List<int> bytes, {
    required String contentType,
    bool scan = true,
  }) async {
    final response = (await _auth.client.postBytes(
      '/receipts',
      bytes,
      contentType: contentType,
      query: scan ? const {'scan': '1'} : null,
      timeout: scanTimeout,
    )).orThrow("We couldn't upload that photo.");
    final json = response.json ?? const {};
    final draft = json['draft'];
    return ReceiptUpload(
      receiptId: json['receiptId'] as int,
      draft: draft is Map<String, dynamic>
          ? ReceiptDraft.fromJson(draft)
          : null,
      scanError: json['scanError'] as String?,
    );
  }

  Future<List<int>> image(int receiptId) =>
      _auth.client.getBytes('/receipts/$receiptId');
}
