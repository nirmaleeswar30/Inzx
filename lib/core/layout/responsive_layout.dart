import 'package:flutter/material.dart';

/// Responsive layout utilities for tablet optimization
class ResponsiveLayout {
  /// Breakpoints
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 900;
  static const double desktopBreakpoint = 1200;

  /// Check device type
  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < mobileBreakpoint;

  static bool isTablet(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= mobileBreakpoint && width < desktopBreakpoint;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= desktopBreakpoint;

  /// Get grid column count based on screen width
  static int getGridCrossAxisCount(
    BuildContext context, {
    int mobile = 2,
    int tablet = 3,
    int desktop = 5,
  }) {
    if (isDesktop(context)) return desktop;
    if (isTablet(context)) return tablet;
    return mobile;
  }

  /// Get horizontal padding based on screen width
  static double getHorizontalPadding(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= desktopBreakpoint) return 48;
    if (width >= tabletBreakpoint) return 32;
    if (width >= mobileBreakpoint) return 24;
    return 16;
  }

  /// Get optimal content width (with max constraint)
  static double getContentWidth(
    BuildContext context, {
    double maxWidth = 1400,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final padding = getHorizontalPadding(context) * 2;
    return (screenWidth - padding).clamp(0, maxWidth);
  }

  /// Check if should show side navigation (tablet/desktop)
  static bool shouldShowSideNav(BuildContext context) =>
      MediaQuery.of(context).size.width >= tabletBreakpoint;

  /// Check if should show bottom player bar (vs full-screen player)
  static bool shouldShowMiniPlayer(BuildContext context) =>
      MediaQuery.of(context).size.width < tabletBreakpoint;

  /// Get player bottom sheet height for tablets
  static double getPlayerSheetHeight(BuildContext context) {
    if (isDesktop(context)) return 400;
    if (isTablet(context)) return 350;
    return MediaQuery.of(context).size.height * 0.9;
  }
}

/// Responsive grid view that adapts column count
class ResponsiveGridView extends StatelessWidget {
  final List<Widget> children;
  final int mobileColumns;
  final int tabletColumns;
  final int desktopColumns;
  final double spacing;
  final double childAspectRatio;
  final EdgeInsets? padding;

  const ResponsiveGridView({
    super.key,
    required this.children,
    this.mobileColumns = 2,
    this.tabletColumns = 3,
    this.desktopColumns = 5,
    this.spacing = 12,
    this.childAspectRatio = 1.0,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final columns = ResponsiveLayout.getGridCrossAxisCount(
      context,
      mobile: mobileColumns,
      tablet: tabletColumns,
      desktop: desktopColumns,
    );

    return GridView.builder(
      padding:
          padding ??
          EdgeInsets.all(ResponsiveLayout.getHorizontalPadding(context)),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
        childAspectRatio: childAspectRatio,
      ),
      itemCount: children.length,
      itemBuilder: (context, index) => children[index],
    );
  }
}

/// Responsive scaffold with optional side navigation
class ResponsiveScaffold extends StatelessWidget {
  final Widget body;
  final int currentIndex;
  final Function(int) onNavTap;
  final List<NavigationDestination> destinations;
  final Widget? floatingActionButton;
  final PreferredSizeWidget? appBar;

  const ResponsiveScaffold({
    super.key,
    required this.body,
    required this.currentIndex,
    required this.onNavTap,
    required this.destinations,
    this.floatingActionButton,
    this.appBar,
  });

  @override
  Widget build(BuildContext context) {
    final showSideNav = ResponsiveLayout.shouldShowSideNav(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (showSideNav) {
      return Scaffold(
        appBar: appBar,
        body: Row(
          children: [
            // Side navigation rail
            NavigationRail(
              selectedIndex: currentIndex,
              onDestinationSelected: onNavTap,
              backgroundColor: isDark
                  ? const Color(0xFF1E1E1E)
                  : Colors.grey.shade50,
              extended: ResponsiveLayout.isDesktop(context),
              labelType: ResponsiveLayout.isDesktop(context)
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.selected,
              destinations: destinations
                  .map(
                    (d) => NavigationRailDestination(
                      icon: d.icon,
                      selectedIcon: d.selectedIcon,
                      label: Text(d.label),
                    ),
                  )
                  .toList(),
            ),
            // Divider
            VerticalDivider(
              width: 1,
              color: isDark ? Colors.white12 : Colors.grey.shade200,
            ),
            // Main content
            Expanded(child: body),
          ],
        ),
        floatingActionButton: floatingActionButton,
      );
    }

    // Mobile layout with bottom navigation
    return Scaffold(
      appBar: appBar,
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: onNavTap,
        destinations: destinations,
      ),
      floatingActionButton: floatingActionButton,
    );
  }
}

/// Centered content container with max width
class ContentContainer extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsets? padding;

  const ContentContainer({
    super.key,
    required this.child,
    this.maxWidth = 1200,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding:
            padding ??
            EdgeInsets.symmetric(
              horizontal: ResponsiveLayout.getHorizontalPadding(context),
            ),
        child: child,
      ),
    );
  }
}

/// Adaptive list/grid layout
class AdaptiveLayout extends StatelessWidget {
  final Widget Function(BuildContext, bool isGrid) builder;

  const AdaptiveLayout({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    final isGrid = !ResponsiveLayout.isMobile(context);
    return builder(context, isGrid);
  }
}

/// Two-pane layout for tablets (list + detail)
class TwoPaneLayout extends StatelessWidget {
  final Widget leftPane;
  final Widget rightPane;
  final double leftPaneWidth;

  const TwoPaneLayout({
    super.key,
    required this.leftPane,
    required this.rightPane,
    this.leftPaneWidth = 350,
  });

  @override
  Widget build(BuildContext context) {
    if (ResponsiveLayout.isMobile(context)) {
      // On mobile, just show left pane (use Navigator for detail)
      return leftPane;
    }

    return Row(
      children: [
        SizedBox(width: leftPaneWidth, child: leftPane),
        VerticalDivider(width: 1),
        Expanded(child: rightPane),
      ],
    );
  }
}
