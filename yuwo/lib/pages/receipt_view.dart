import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/receipt_service.dart';
import '../theme/app_theme.dart';

/// The receipt photo behind a bill. Pinch to zoom.
class ReceiptViewPage extends StatefulWidget {
  const ReceiptViewPage({super.key, required this.receiptId, this.title});

  final int receiptId;
  final String? title;

  @override
  State<ReceiptViewPage> createState() => _ReceiptViewPageState();
}

class _ReceiptViewPageState extends State<ReceiptViewPage> {
  late final Future<List<int>> _image = ReceiptService(
    AuthScope.read(context),
  ).image(widget.receiptId);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.title == null ? 'Receipt' : 'Receipt · ${widget.title}',
          style: AppText.sectionTitle.copyWith(
            fontSize: 16,
            color: Colors.white,
          ),
        ),
      ),
      body: FutureBuilder<List<int>>(
        future: _image,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final error = snapshot.error;
            return Center(
              child: Text(
                error is ApiException
                    ? error.message
                    : "Couldn't load the receipt.",
                style: AppText.body.copyWith(color: Colors.white),
              ),
            );
          }
          final bytes = snapshot.data;
          if (bytes == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return InteractiveViewer(
            maxScale: 5,
            child: Center(
              child: Image.memory(
                Uint8List.fromList(bytes),
                semanticLabel: 'Receipt photo',
              ),
            ),
          );
        },
      ),
    );
  }
}
