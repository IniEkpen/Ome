import 'package:flutter/material.dart';

import '../groups/groupmodel.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
