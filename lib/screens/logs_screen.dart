import 'dart:async';
import '../core/utils/platform_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:marquee/marquee.dart';
import 'package:share_plus/share_plus.dart';
import '../core/design_system/design_system.dart';
import '../core/utils/app_logger.dart';
import '../providers/providers.dart';

/// Screen to view, filter, search, copy and export rolling application logs and crash traces.
class AppLogsScreen extends ConsumerStatefulWidget {
  const AppLogsScreen({super.key});

  @override
  ConsumerState<AppLogsScreen> createState() => _AppLogsScreenState();
}

class _AppLogsScreenState extends ConsumerState<AppLogsScreen> {
  StreamSubscription<LogEntry>? _logSubscription;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  LogLevel? _selectedLevel; // null = All
  String _searchQuery = '';
  bool _isSearching = false;
  bool _newestFirst = true;
  int _logFileSize = 0;
  final Set<int> _expandedEntries = <int>{};

  @override
  void initState() {
    super.initState();
    _loadFileSize();
    _logSubscription = AppLogger.onNewLog.listen((_) {
      if (mounted) {
        setState(() {});
        _loadFileSize();
      }
    });
  }

  @override
  void dispose() {
    _logSubscription?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadFileSize() async {
    final size = await AppLogger.getLogFileSize();
    if (mounted) {
      setState(() => _logFileSize = size);
    }
  }

  List<LogEntry> _getFilteredEntries() {
    var list = AppLogger.entries.where((entry) {
      if (_selectedLevel != null && entry.level != _selectedLevel) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchesTag = entry.tag.toLowerCase().contains(q);
        final matchesMsg = entry.message.toLowerCase().contains(q);
        final matchesStack =
            entry.stackTrace?.toLowerCase().contains(q) ?? false;
        if (!matchesTag && !matchesMsg && !matchesStack) {
          return false;
        }
      }
      return true;
    }).toList();

    if (_newestFirst) {
      list = list.reversed.toList();
    }
    return list;
  }

  int _countForLevel(LogLevel? level) {
    if (level == null) return AppLogger.entries.length;
    return AppLogger.entries.where((e) => e.level == level).length;
  }

  Future<void> _copyAllLogs() async {
    final formatted = await AppLogger.getFormattedLogs();
    await Clipboard.setData(ClipboardData(text: formatted));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('All logs and system diagnostics copied to clipboard'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _shareLogFile() async {
    try {
      final file = await AppLogger.exportLogFile();
      if (file == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No log file available to share'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Inzx App Logs & Diagnostics',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to share log file: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _confirmClearLogs() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear All Logs?'),
        content: const Text(
          'This will permanently erase the current log file and in-memory trace history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await AppLogger.clearLogs();
      _expandedEntries.clear();
      await _loadFileSize();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Logs cleared'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = ref.watch(effectiveAccentColorProvider);
    final filtered = _getFilteredEntries();

    return Scaffold(
      backgroundColor: desktopPageBackground(isDark ? InzxColors.darkBackground : InzxColors.background),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(
                  color: isDark ? Colors.white : InzxColors.textPrimary,
                  fontSize: 15,
                ),
                decoration: InputDecoration(
                  hintText: 'Search logs, tags, stack traces...',
                  hintStyle: TextStyle(
                    color: isDark ? Colors.white38 : InzxColors.textTertiary,
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                ),
                onChanged: (val) {
                  setState(() => _searchQuery = val);
                },
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 22,
                    child: Marquee(
                      text: 'App Logs & Diagnostics',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : InzxColors.textPrimary,
                      ),
                      scrollAxis: Axis.horizontal,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      blankSpace: 35.0,
                      velocity: 25.0,
                      pauseAfterRound: const Duration(seconds: 2),
                      startPadding: 0.0,
                      accelerationDuration: const Duration(seconds: 1),
                      accelerationCurve: Curves.linear,
                      decelerationDuration: const Duration(milliseconds: 500),
                      decelerationCurve: Curves.easeOut,
                    ),
                  ),
                  Text(
                    '${AppLogger.entryCount} events • ${AppLogger.formatBytes(_logFileSize)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white54 : InzxColors.textSecondary,
                    ),
                  ),
                ],
              ),
        actions: [
          IconButton(
            tooltip: _isSearching ? 'Close search' : 'Search logs',
            icon: Icon(
              _isSearching ? Icons.close_rounded : Iconsax.search_normal_1,
              size: 20,
            ),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchQuery = '';
                  _searchController.clear();
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
          IconButton(
            tooltip: _newestFirst ? 'Newest first' : 'Oldest first',
            icon: Icon(
              _newestFirst ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
              size: 20,
            ),
            onPressed: () {
              setState(() => _newestFirst = !_newestFirst);
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (val) {
              if (val == 'copy') _copyAllLogs();
              if (val == 'share') _shareLogFile();
              if (val == 'clear') _confirmClearLogs();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'copy',
                child: Row(
                  children: [
                    Icon(Iconsax.copy, size: 18),
                    SizedBox(width: 12),
                    Text('Copy all logs'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'share',
                child: Row(
                  children: [
                    Icon(Iconsax.export_1, size: 18),
                    SizedBox(width: 12),
                    Text('Export / Share .log'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Iconsax.trash, color: Colors.red, size: 18),
                    SizedBox(width: 12),
                    Text('Clear logs', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter tabs
          _buildFilterBar(accentColor, isDark),
          // Log entries list
          Expanded(
            child: filtered.isEmpty
                ? _buildEmptyState(isDark)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final entry = filtered[index];
                      final isExpanded = _expandedEntries.contains(entry.hashCode);
                      return _buildLogTile(entry, isExpanded, isDark, accentColor);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(Color accentColor, bool isDark) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          _buildFilterChip('All (${_countForLevel(null)})', null, accentColor, isDark),
          const SizedBox(width: 8),
          _buildFilterChip(
            'Errors (${_countForLevel(LogLevel.error)})',
            LogLevel.error,
            Colors.redAccent,
            isDark,
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            'Warnings (${_countForLevel(LogLevel.warning)})',
            LogLevel.warning,
            Colors.amber.shade700,
            isDark,
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            'Info (${_countForLevel(LogLevel.info)})',
            LogLevel.info,
            Colors.teal,
            isDark,
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            'Debug (${_countForLevel(LogLevel.debug)})',
            LogLevel.debug,
            Colors.grey,
            isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(
    String label,
    LogLevel? level,
    Color color,
    bool isDark,
  ) {
    final isSelected = _selectedLevel == level;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected
              ? Colors.white
              : (isDark ? Colors.white70 : InzxColors.textSecondary),
        ),
      ),
      selected: isSelected,
      selectedColor: color,
      backgroundColor: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected ? color : Colors.transparent,
          width: 1,
        ),
      ),
      onSelected: (_) {
        setState(() => _selectedLevel = level);
      },
    );
  }

  Widget _buildLogTile(
    LogEntry entry,
    bool isExpanded,
    bool isDark,
    Color accentColor,
  ) {
    final levelColor = _getLevelColor(entry.level);
    final hasStack = entry.stackTrace != null && entry.stackTrace!.isNotEmpty;

    final timeStr =
        '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
        '${entry.timestamp.minute.toString().padLeft(2, '0')}:'
        '${entry.timestamp.second.toString().padLeft(2, '0')}.'
        '${entry.timestamp.millisecond.toString().padLeft(3, '0')}';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF181818) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: entry.level == LogLevel.error
              ? Colors.red.withValues(alpha: 0.3)
              : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06)),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: hasStack
            ? () {
                setState(() {
                  if (isExpanded) {
                    _expandedEntries.remove(entry.hashCode);
                  } else {
                    _expandedEntries.add(entry.hashCode);
                  }
                });
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Meta header: level pill, tag, timestamp
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: levelColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      entry.level.label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: levelColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '[${entry.tag}]',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : InzxColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.white38 : InzxColors.textTertiary,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Message
              SelectableText(
                entry.message,
                style: TextStyle(
                  fontSize: 12.5,
                  fontFamily: 'monospace',
                  color: isDark ? Colors.white : InzxColors.textPrimary,
                ),
              ),
              // Stack trace indicator / expansion
              if (hasStack) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      isExpanded ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                      size: 16,
                      color: levelColor,
                    ),
                    Text(
                      isExpanded ? 'Hide stack trace' : 'Tap to view stack trace',
                      style: TextStyle(
                        fontSize: 11,
                        color: levelColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Iconsax.copy, size: 14),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Copy stack trace',
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: entry.stackTrace!),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Stack trace copied'),
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                if (isExpanded) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.black45 : const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isDark ? Colors.white12 : Colors.black12,
                      ),
                    ),
                    child: SelectableText(
                      entry.stackTrace!,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontFamily: 'monospace',
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _getLevelColor(LogLevel level) {
    switch (level) {
      case LogLevel.error:
        return Colors.redAccent;
      case LogLevel.warning:
        return Colors.amber.shade700;
      case LogLevel.info:
        return Colors.teal;
      case LogLevel.debug:
        return Colors.blueGrey;
    }
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Iconsax.document_code,
            size: 48,
            color: isDark ? Colors.white24 : Colors.black26,
          ),
          const SizedBox(height: 12),
          Text(
            _searchQuery.isNotEmpty
                ? 'No matching logs found'
                : 'No logs recorded yet',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white54 : InzxColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
