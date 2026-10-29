import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../transactiongraph.dart';

/// Looks up users whose username matches [query], best match first.
typedef UserSearch = Future<List<Party>> Function(String query);

/// Search bar that suggests real accounts as you type and hands the chosen
/// one to [onSelected]. Only users returned by [search] can be picked, so
/// callers never receive a made-up username.
///
/// - Debounced lookups; responses for anything but the latest query are dropped.
/// - Matched letters are bold in each suggestion.
/// - The rest of the top suggestion shows as grey inline text; Tab or the
///   right arrow fills it in. Enter adds the highlighted suggestion.
/// - Up/down arrows move the highlight, Escape closes the list.
class UsernameSearchField extends StatefulWidget {
  const UsernameSearchField({
    super.key,
    required this.search,
    required this.onSelected,
    this.excluded = const {},
    this.hintText = 'Search usernames',
    this.debounce = const Duration(milliseconds: 250),
  });

  final UserSearch search;
  final ValueChanged<Party> onSelected;

  /// Lower-case usernames to leave out of the suggestions, e.g. users that
  /// are already added.
  final Set<String> excluded;
  final String hintText;
  final Duration debounce;

  /// The server caps usernames at 30 characters and ignores longer queries.
  static const maxQueryLength = 30;

  @override
  State<UsernameSearchField> createState() => _UsernameSearchFieldState();
}

class _UsernameSearchFieldState extends State<UsernameSearchField> {
  static const _tileHeight = 56.0;
  static const _maxVisibleTiles = 5;
  static final _searchable = RegExp(r'^[A-Za-z0-9_.]+$');

  final _controller = _GhostTextController();
  late final _focus = FocusNode(onKeyEvent: _onKey);
  final _overlay = OverlayPortalController();
  final _link = LayerLink();
  final _scroll = ScrollController();

  Timer? _debounce;
  // Bumped on every edit so responses for older queries are ignored.
  int _version = 0;
  List<Party> _results = const [];
  // The query [_results] answer; differs from the text while a search is due.
  String _resultsQuery = '';
  bool _loading = false;
  String? _error;
  int _highlight = 0;
  // Enter was pressed before results for the current text arrived.
  bool _selectWhenReady = false;

  String get _query => _controller.text.trim();

  List<Party> get _options => [
    for (final user in _results)
      if (!widget.excluded.contains(user.label.toLowerCase())) user,
  ];

  Party? get _highlighted {
    final options = _options;
    return options.isEmpty
        ? null
        : options[_highlight.clamp(0, options.length - 1)];
  }

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
    // Caret moves (not just edits) decide whether the ghost text shows.
    _controller.addListener(_updateGhost);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focus.dispose();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focus.hasFocus) {
      if (_query.isNotEmpty) _overlay.show();
    } else {
      _overlay.hide();
    }
    _updateGhost();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    final query = _query;
    final version = ++_version;
    setState(() {
      _highlight = 0;
      _error = null;
      _selectWhenReady = false;
      if (query.isEmpty) {
        _results = const [];
        _resultsQuery = '';
        _loading = false;
      } else if (query.length > UsernameSearchField.maxQueryLength ||
          !_searchable.hasMatch(query)) {
        // Can't match any username; no need to ask the server.
        _results = const [];
        _resultsQuery = query;
        _loading = false;
      } else {
        _loading = true;
        _debounce = Timer(widget.debounce, () => _runSearch(query, version));
      }
    });
    query.isEmpty ? _overlay.hide() : _overlay.show();
    _updateGhost();
  }

  Future<void> _runSearch(String query, int version) async {
    _debounce?.cancel();
    if (mounted && !_loading) setState(() => _loading = true);
    List<Party> results;
    try {
      results = await widget.search(query);
    } catch (_) {
      if (!mounted || version != _version) return;
      setState(() {
        _loading = false;
        _selectWhenReady = false;
        _results = const [];
        _resultsQuery = query;
        _error = "Couldn't search users. Check your connection.";
      });
      _updateGhost();
      return;
    }
    if (!mounted || version != _version) return;
    setState(() {
      _loading = false;
      _results = results;
      _resultsQuery = query;
      _highlight = 0;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    if (_selectWhenReady) {
      _selectWhenReady = false;
      final top = _highlighted;
      if (top != null) {
        _select(top);
        return;
      }
    }
    _updateGhost();
  }

  void _select(Party user) {
    widget.onSelected(user);
    _reset();
    _focus.requestFocus();
  }

  void _reset() {
    _debounce?.cancel();
    _version++;
    _controller.clear();
    setState(() {
      _results = const [];
      _resultsQuery = '';
      _loading = false;
      _error = null;
      _highlight = 0;
      _selectWhenReady = false;
    });
    _overlay.hide();
    _updateGhost();
  }

  void _onSubmitted(String _) {
    final query = _query;
    if (query.isEmpty) return;
    final options = _options;
    if (_resultsQuery == query && options.isNotEmpty) {
      return _select(_highlighted!);
    }
    // Results are for older text; an exact match among them is still safe.
    final lower = query.toLowerCase();
    for (final user in options) {
      if (user.label.toLowerCase() == lower) return _select(user);
    }
    if (_resultsQuery == query && _error == null) return; // No users found.
    // Search now and pick the top result when it arrives.
    _selectWhenReady = true;
    if (_debounce?.isActive ?? false) {
      _runSearch(query, _version);
    } else if (!_loading) {
      _runSearch(query, ++_version);
    }
  }

  /// Shows the rest of the highlighted suggestion after the caret when the
  /// suggestion starts with what was typed.
  void _updateGhost() {
    final text = _controller.text;
    final selection = _controller.selection;
    final user = _highlighted;
    final label = user?.label ?? '';
    final caretAtEnd =
        !selection.isValid ||
        (selection.isCollapsed && selection.baseOffset == text.length);
    _controller.ghost =
        _focus.hasFocus &&
            caretAtEnd &&
            text.isNotEmpty &&
            label.length > text.length &&
            label.toLowerCase().startsWith(text.toLowerCase())
        ? label.substring(text.length)
        : '';
  }

  void _acceptGhost() {
    final user = _highlighted;
    if (user == null) return;
    _controller.value = TextEditingValue(
      text: user.label,
      selection: TextSelection.collapsed(offset: user.label.length),
    );
    _onChanged(user.label);
  }

  void _moveHighlight(int delta) {
    final count = _options.length;
    if (count == 0) return;
    setState(() => _highlight = (_highlight + delta) % count);
    _updateGhost();
    if (!_scroll.hasClients) return;
    final top = _highlight * _tileHeight;
    final position = _scroll.position;
    if (top < position.pixels) {
      _scroll.jumpTo(top);
    } else if (top + _tileHeight >
        position.pixels + position.viewportDimension) {
      _scroll.jumpTo(top + _tileHeight - position.viewportDimension);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final listOpen = _overlay.isShowing && _options.isNotEmpty;
    if (key == LogicalKeyboardKey.arrowDown && listOpen) {
      _moveHighlight(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp && listOpen) {
      _moveHighlight(-1);
      return KeyEventResult.handled;
    }
    if ((key == LogicalKeyboardKey.tab ||
            key == LogicalKeyboardKey.arrowRight) &&
        _controller.ghost.isNotEmpty) {
      _acceptGhost();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape && _overlay.isShowing) {
      _overlay.hide();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => CompositedTransformTarget(
        link: _link,
        child: OverlayPortal(
          controller: _overlay,
          overlayChildBuilder: (_) => CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomLeft,
            offset: const Offset(0, 4),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: constraints.maxWidth,
                // Taps here count as inside the field, so it keeps focus.
                child: TextFieldTapRegion(child: _buildSuggestions()),
              ),
            ),
          ),
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.search,
            inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
            onChanged: _onChanged,
            onSubmitted: _onSubmitted,
            // Keep focus after Enter so several members can be added in a row.
            onEditingComplete: () {},
            onTapOutside: (_) => _focus.unfocus(),
            decoration: InputDecoration(
              hintText: widget.hintText,
              prefixIcon: const Icon(Icons.search, color: AppColors.hint),
              suffixIcon: _buildSuffix(),
            ),
          ),
        ),
      ),
    );
  }

  Widget? _buildSuffix() {
    if (!_loading && _controller.text.isEmpty) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_loading)
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        if (_controller.text.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Clear',
            onPressed: () {
              _reset();
              _focus.requestFocus();
            },
          )
        else
          const SizedBox(width: 12),
      ],
    );
  }

  Widget _buildSuggestions() {
    final query = _query;
    final options = _options;
    final Widget content;
    if (_error != null) {
      content = _message(
        _error!,
        AppText.caption.copyWith(color: AppColors.error),
      );
    } else if (options.isNotEmpty) {
      content = ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: _tileHeight * math.min(options.length, _maxVisibleTiles),
        ),
        child: ListView.builder(
          controller: _scroll,
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          itemExtent: _tileHeight,
          itemCount: options.length,
          itemBuilder: (context, i) => _SuggestionTile(
            user: options[i],
            query: query,
            highlighted: i == _highlight.clamp(0, options.length - 1),
            onTap: () => _select(options[i]),
          ),
        ),
      );
    } else if (_loading || _resultsQuery != query) {
      content = _message('Searching…', AppText.caption);
    } else {
      content = _message('No users found', AppText.caption);
    }
    return Material(
      color: AppColors.surface,
      elevation: 4,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(AppRadius.control),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }

  Widget _message(String text, TextStyle style) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Text(text, style: style),
  );
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({
    required this.user,
    required this.query,
    required this.highlighted,
    required this.onTap,
  });

  final Party user;
  final String query;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final matched = usernameMatchIndices(user.label, query);
    final base = AppText.body.copyWith(color: AppColors.textPrimary);
    final bold = base.copyWith(fontWeight: FontWeight.w700);
    final name = user.name?.trim() ?? '';
    return Material(
      color: highlighted ? AppColors.background : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    for (var i = 0; i < user.label.length; i++)
                      TextSpan(
                        text: user.label[i],
                        style: matched.contains(i) ? bold : base,
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (name.isNotEmpty)
                Text(
                  name,
                  style: AppText.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Indices of [label] that match [query], case-insensitively, mirroring the
/// server's ranking: a contiguous match if there is one, otherwise the
/// query's letters found in order. Empty when [query] doesn't match.
Set<int> usernameMatchIndices(String label, String query) {
  final text = label.toLowerCase();
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const {};
  final start = text.indexOf(q);
  if (start >= 0) {
    return {for (var i = start; i < start + q.length; i++) i};
  }
  final indices = <int>{};
  var from = 0;
  for (final char in q.split('')) {
    final at = text.indexOf(char, from);
    if (at < 0) return const {};
    indices.add(at);
    from = at + 1;
  }
  return indices;
}

/// Draws [ghost] in grey after the typed text, without making it part of
/// the value.
class _GhostTextController extends TextEditingController {
  String _ghost = '';

  String get ghost => _ghost;

  set ghost(String value) {
    if (value == _ghost) return;
    _ghost = value;
    notifyListeners();
  }

  @override
  set value(TextEditingValue newValue) {
    if (newValue.text != text) _ghost = '';
    // Taps on the ghost text land past the end of the real text; keep the
    // caret inside it.
    final length = newValue.text.length;
    final selection = newValue.selection;
    if (selection.isValid &&
        (selection.baseOffset > length || selection.extentOffset > length)) {
      newValue = newValue.copyWith(
        selection: selection.copyWith(
          baseOffset: math.min(selection.baseOffset, length),
          extentOffset: math.min(selection.extentOffset, length),
        ),
      );
    }
    super.value = newValue;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final typed = super.buildTextSpan(
      context: context,
      style: style,
      withComposing: withComposing,
    );
    if (_ghost.isEmpty) return typed;
    return TextSpan(
      style: style,
      children: [
        typed,
        TextSpan(
          text: _ghost,
          style: (style ?? const TextStyle()).copyWith(color: AppColors.hint),
        ),
      ],
    );
  }
}
