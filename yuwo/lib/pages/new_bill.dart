import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../groups/groupmodel.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/receipt_service.dart';
import '../splits/split_model.dart';
import '../splits/split_service.dart';
import '../theme/app_theme.dart';
import '../utils/money.dart';
import '../widgets/common.dart';

/// The group owner enters the bill. Starting it opens the synced payment
/// popup for everyone in the group. Pops with the new [SplitBill].
class NewBillPage extends StatefulWidget {
  const NewBillPage({super.key, required this.group});

  final GroupModel group;

  @override
  State<NewBillPage> createState() => _NewBillPageState();
}

class _ItemRow {
  final name = TextEditingController();
  final quantity = TextEditingController(text: '1');
  final price = TextEditingController();

  void dispose() {
    name.dispose();
    quantity.dispose();
    price.dispose();
  }
}

class _NewBillPageState extends State<NewBillPage> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _tax = TextEditingController();
  final _tip = TextEditingController();
  final List<_ItemRow> _items = [_ItemRow()];
  final Set<String> _coHosts = {};
  bool _loading = false;

  // The scanned receipt, attached to the bill when it's sent.
  bool _scanning = false;
  int? _receiptId;
  Uint8List? _receiptPhoto;
  String? _merchantName;
  String? _receiptDate;
  int? _receiptTotalCents;

  @override
  void dispose() {
    _title.dispose();
    _tax.dispose();
    _tip.dispose();
    for (final row in _items) {
      row.dispose();
    }
    super.dispose();
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  String? _money(String? value, {bool optional = false}) {
    if (optional && (value == null || value.trim().isEmpty)) return null;
    return Money.parse(value ?? '') == null
        ? 'Enter an amount like 12.50'
        : null;
  }

  String? _quantity(String? value) {
    final n = int.tryParse(value ?? '');
    return n == null || n < 1 || n > 99 ? '1-99' : null;
  }

  Future<void> _scanReceipt() async {
    // The camera isn't offered on the web; the photo library opens a file picker.
    final source = kIsWeb
        ? ImageSource.gallery
        : await showModalBottomSheet<ImageSource>(
            context: context,
            showDragHandle: true,
            backgroundColor: AppColors.surface,
            builder: (context) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.photo_camera_outlined),
                    title: const Text('Take a photo'),
                    onTap: () => Navigator.pop(context, ImageSource.camera),
                  ),
                  ListTile(
                    leading: const Icon(Icons.photo_library_outlined),
                    title: const Text('Choose from photos'),
                    onTap: () => Navigator.pop(context, ImageSource.gallery),
                  ),
                ],
              ),
            ),
          );
    if (source == null || !mounted) return;
    // Small enough to upload quickly, sharp enough to read.
    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 2400,
      imageQuality: 75,
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    await _uploadReceipt(bytes, file.mimeType ?? _typeFor(file.name));
  }

  /// Uploads and reads the photo, then fills in the form from it.
  Future<void> _uploadReceipt(Uint8List bytes, String contentType) async {
    setState(() => _scanning = true);
    try {
      final upload = await ReceiptService(
        AuthScope.read(context),
      ).upload(bytes, contentType: contentType);
      if (!mounted) return;
      setState(() {
        _receiptId = upload.receiptId;
        _receiptPhoto = bytes;
        final draft = upload.draft;
        if (draft != null) _fillFrom(draft);
      });
      final read = upload.draft?.items.length ?? 0;
      showMessage(
        context,
        upload.scanError ??
            'Read $read item${read == 1 ? '' : 's'}. Check them before sending.',
      );
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  static String _typeFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }

  String _dollars(int cents) => (cents / 100).toStringAsFixed(2);

  void _fillFrom(ReceiptDraft draft) {
    _merchantName = draft.merchantName;
    _receiptDate = draft.receiptDate;
    _receiptTotalCents = draft.totalCents;
    if (_title.text.trim().isEmpty && draft.merchantName != null) {
      _title.text = draft.merchantName!;
    }
    if (draft.items.isNotEmpty) {
      for (final row in _items) {
        row.dispose();
      }
      _items
        ..clear()
        ..addAll([
          for (final item in draft.items)
            _ItemRow()
              ..name.text = item.name
              ..quantity.text = '${item.quantity}'
              ..price.text = _dollars(item.unitPriceCents),
        ]);
    }
    if (draft.taxCents != null) _tax.text = _dollars(draft.taxCents!);
    if (draft.tipCents != null) _tip.text = _dollars(draft.tipCents!);
  }

  void _removeReceipt() => setState(() {
    _receiptId = null;
    _receiptPhoto = null;
    _merchantName = null;
    _receiptDate = null;
    _receiptTotalCents = null;
  });

  /// Items + tax + tip as entered, or null while something doesn't parse.
  int? get _enteredTotalCents {
    var total = 0;
    for (final row in _items) {
      final price = Money.parse(row.price.text);
      final quantity = int.tryParse(row.quantity.text);
      if (price == null || quantity == null) return null;
      total += price * quantity;
    }
    for (final extra in [_tax.text, _tip.text]) {
      if (extra.trim().isEmpty) continue;
      final cents = Money.parse(extra);
      if (cents == null) return null;
      total += cents;
    }
    return total;
  }

  Future<void> _submit() async {
    if (_loading || !_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final split = await SplitService(AuthScope.read(context)).startSplit(
        widget.group.id,
        title: _title.text.trim(),
        items: [
          for (final row in _items)
            NewBillItem(
              name: row.name.text.trim(),
              quantity: int.parse(row.quantity.text),
              unitPriceCents: Money.parse(row.price.text)!,
            ),
        ],
        taxCents: Money.parse(_tax.text.isEmpty ? '0' : _tax.text)!,
        tipCents: Money.parse(_tip.text.isEmpty ? '0' : _tip.text)!,
        coHosts: _coHosts.toList(),
        merchantName: _merchantName,
        receiptDate: _receiptDate,
        receiptId: _receiptId,
      );
      if (mounted) Navigator.pop(context, split);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = AuthScope.of(context).session?.username;
    final others = widget.group.people.where((p) => p != me).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'New bill',
          style: AppText.sectionTitle.copyWith(fontSize: 16),
        ),
      ),
      body: PageBody(
        child: Form(
          key: _formKey,
          // Rebuilds the "adds up to" check as amounts are typed.
          onChanged: () => setState(() {}),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ReceiptCard(
                photo: _receiptPhoto,
                scanning: _scanning,
                onScan: _scanReceipt,
                onRemove: _removeReceipt,
              ),
              const SizedBox(height: AppSpacing.gap),
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(
                  hintText: 'Where? e.g. The Tack Room',
                ),
                validator: _required,
              ),
              const SizedBox(height: AppSpacing.gap),
              const SectionHeader('Items', subtitle: 'Price is per item'),
              const SizedBox(height: AppSpacing.field),
              for (var i = 0; i < _items.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.field),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 8,
                    children: [
                      Expanded(
                        flex: 5,
                        child: TextFormField(
                          controller: _items[i].name,
                          decoration: const InputDecoration(hintText: 'Item'),
                          validator: _required,
                        ),
                      ),
                      SizedBox(
                        width: 56,
                        child: TextFormField(
                          controller: _items[i].quantity,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(hintText: 'Qty'),
                          validator: _quantity,
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _items[i].price,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Price',
                            prefixText: '\$',
                          ),
                          validator: _money,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove item',
                        onPressed: _items.length == 1
                            ? null
                            : () =>
                                  setState(() => _items.removeAt(i).dispose()),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                    ],
                  ),
                ),
              OutlinedButton.icon(
                onPressed: () => setState(() => _items.add(_ItemRow())),
                icon: const Icon(Icons.add),
                label: const Text('Add item'),
              ),
              const SizedBox(height: AppSpacing.gap),
              Row(
                spacing: AppSpacing.field,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _tax,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Tax',
                        prefixText: '\$',
                      ),
                      validator: (v) => _money(v, optional: true),
                    ),
                  ),
                  Expanded(
                    child: TextFormField(
                      controller: _tip,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Tip',
                        prefixText: '\$',
                      ),
                      validator: (v) => _money(v, optional: true),
                    ),
                  ),
                ],
              ),
              if (others.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.gap),
                const SectionHeader(
                  'Co-hosts',
                  subtitle:
                      "You're paying the bill. Add anyone splitting the cost of covering it with you.",
                ),
                const SizedBox(height: AppSpacing.field),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final name in others)
                      FilterChip(
                        label: Text(name),
                        selected: _coHosts.contains(name),
                        onSelected: (on) => setState(
                          () => on ? _coHosts.add(name) : _coHosts.remove(name),
                        ),
                      ),
                  ],
                ),
              ],
              if (_receiptTotalCents != null &&
                  _enteredTotalCents != null &&
                  _enteredTotalCents != _receiptTotalCents) ...[
                const SizedBox(height: AppSpacing.gap),
                Text(
                  'These add up to ${Money.format(_enteredTotalCents!)}, but '
                  'the receipt says ${Money.format(_receiptTotalCents!)}. '
                  'Check the items before sending.',
                  style: AppText.body.copyWith(color: AppColors.error),
                ),
              ],
              const SizedBox(height: AppSpacing.section),
              LoadingButton(
                label: 'Send to the group',
                loading: _loading,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Scan a receipt, or show the one attached.
class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({
    required this.photo,
    required this.scanning,
    required this.onScan,
    required this.onRemove,
  });

  final Uint8List? photo;
  final bool scanning;
  final VoidCallback onScan;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    if (scanning) {
      return AppCard(
        child: Row(
          children: [
            const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AppSpacing.field),
            Expanded(
              child: Text(
                'Reading the receipt… this can take up to a minute.',
                style: AppText.body,
              ),
            ),
          ],
        ),
      );
    }
    final image = photo;
    if (image == null) {
      return OutlinedButton.icon(
        onPressed: onScan,
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text('Scan receipt'),
      );
    }
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.tile),
            child: Image.memory(
              image,
              width: 56,
              height: 72,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: AppSpacing.field),
          const Expanded(
            child: SectionHeader(
              'Receipt attached',
              subtitle: 'Everyone in the group can see it',
            ),
          ),
          TextButton(onPressed: onRemove, child: const Text('Remove')),
        ],
      ),
    );
  }
}
