import 'package:flutter/material.dart';

import '../../api/api_exception.dart';

/// Shared palette for the admin console, tuned to the dark premium reference.
class AdminPalette {
  static const Color bg0 = Color(0xFF0A0712);
  static const Color bg1 = Color(0xFF130B22);
  // Premium glass wash for input/search fields (replaces the heavy bg1 box).
  static const Color inputGlass = Color(0x0DFFFFFF); // white @ 0.05
  static const Color panel = Color(0xFF15101F);
  static const Color panelSoft = Color(0xFF1B1430);
  static const Color border = Color(0x1AFFFFFF);
  static const Color borderStrong = Color(0x33FFFFFF);
  static const Color text = Color(0xFFF4F1FB);
  static const Color textDim = Color(0xFF9C93B5);
  static const Color violet = Color(0xFFA855F7);
  static const Color blue = Color(0xFF4CC9F0);
  static const Color green = Color(0xFF22C55E);
  static const Color amber = Color(0xFFFFB703);
  static const Color red = Color(0xFFEF4444);
  static const Color pink = Color(0xFFF72585);
}

/// Full-bleed dark gradient background with a subtle glow, matching the
/// reference admin screenshots.
class AdminBackground extends StatelessWidget {
  const AdminBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.6, -0.9),
          radius: 1.6,
          colors: [Color(0xFF1E1233), AdminPalette.bg0],
          stops: [0.0, 0.7],
        ),
      ),
      child: SizedBox.expand(),
    );
  }
}

/// A clean bordered panel used across every admin section.
class AdminPanel extends StatelessWidget {
  const AdminPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AdminPalette.panel, AdminPalette.panelSoft],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AdminPalette.border),
      ),
      child: child,
    );
  }
}

/// Panel title with a small leading icon (e.g. "Active Engines").
class AdminPanelHeader extends StatelessWidget {
  const AdminPanelHeader({super.key, required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AdminPalette.violet, size: 20),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            color: AdminPalette.text,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

/// Metric card with icon, a "Live" pill, a label and a value. When [value] is
/// null an em-dash is shown so the card never looks broken.
class AdminMetricCard extends StatelessWidget {
  const AdminMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.live = true,
  });

  final String label;
  final String? value;
  final IconData icon;
  final Color color;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return AdminPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withOpacity(0.32)),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const Spacer(),
              if (live)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AdminPalette.border),
                  ),
                  child: const Text(
                    'Live',
                    style: TextStyle(
                      color: AdminPalette.textDim,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: AdminPalette.textDim,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value ?? '—',
              style: const TextStyle(
                color: AdminPalette.text,
                fontSize: 30,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Responsive grid of metric cards.
class AdminMetricGrid extends StatelessWidget {
  const AdminMetricGrid({super.key, required this.cards});

  final List<AdminMetricCard> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width > 900 ? 4 : (width > 560 ? 2 : 1);
        const spacing = 16.0;
        final cardWidth = (width - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final card in cards)
              SizedBox(width: cardWidth, child: card),
          ],
        );
      },
    );
  }
}

/// Intentional, polished empty state (never looks like an error).
class AdminEmptyState extends StatelessWidget {
  const AdminEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? 24 : 40, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AdminPalette.textDim, size: compact ? 34 : 44),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AdminPalette.text,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AdminPalette.textDim,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small colored status pill.
class AdminStatusPill extends StatelessWidget {
  const AdminStatusPill({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Generic async wrapper that renders loading / auth / error / success states
/// for any admin endpoint so every section behaves consistently.
class AdminAsyncView<T> extends StatelessWidget {
  const AdminAsyncView({
    super.key,
    required this.future,
    required this.onRetry,
    required this.builder,
  });

  final Future<T> future;
  final VoidCallback onRetry;
  final Widget Function(BuildContext context, T data) builder;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _AdminLoading();
        }
        if (snapshot.hasError) {
          return _AdminErrorState(error: snapshot.error!, onRetry: onRetry);
        }
        if (!snapshot.hasData) {
          return _AdminErrorState(
            error: 'No data returned.',
            onRetry: onRetry,
          );
        }
        return builder(context, snapshot.data as T);
      },
    );
  }
}

/// Stateful loader that (re)creates its future when [refreshTick] changes and
/// exposes an internal retry. Keeps section widgets free of boilerplate.
class AdminSectionLoader<T> extends StatefulWidget {
  const AdminSectionLoader({
    super.key,
    required this.refreshTick,
    required this.loader,
    required this.builder,
  });

  final int refreshTick;
  final Future<T> Function() loader;
  final Widget Function(BuildContext context, T data) builder;

  @override
  State<AdminSectionLoader<T>> createState() => _AdminSectionLoaderState<T>();
}

class _AdminSectionLoaderState<T> extends State<AdminSectionLoader<T>> {
  late Future<T> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loader();
  }

  @override
  void didUpdateWidget(covariant AdminSectionLoader<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTick != widget.refreshTick) {
      _future = widget.loader();
    }
  }

  void _retry() => setState(() => _future = widget.loader());

  @override
  Widget build(BuildContext context) {
    return AdminAsyncView<T>(
      future: _future,
      onRetry: _retry,
      builder: widget.builder,
    );
  }
}

class _AdminLoading extends StatelessWidget {
  const _AdminLoading();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 260,
      child: Center(
        child: SizedBox(
          width: 30,
          height: 30,
          child: CircularProgressIndicator(
            strokeWidth: 2.6,
            color: AdminPalette.violet,
          ),
        ),
      ),
    );
  }
}

class _AdminErrorState extends StatelessWidget {
  const _AdminErrorState({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    String title = 'Something went wrong';
    String message = 'Unable to load this section right now.';
    IconData icon = Icons.error_outline_rounded;

    if (error is ApiException) {
      final api = error as ApiException;
      switch (api.statusCode) {
        case 401:
          title = 'You are not signed in';
          message =
              'Sign in with an administrator account to open the console.';
          icon = Icons.lock_outline_rounded;
          break;
        case 403:
          title = 'Admin access required';
          message =
              'Your account does not have the admin role for this console.';
          icon = Icons.shield_outlined;
          break;
        default:
          title = 'Backend unavailable';
          message = api.message;
          icon = Icons.cloud_off_rounded;
      }
    } else {
      title = 'Backend offline';
      message = 'The admin API could not be reached. Check the connection.';
      icon = Icons.cloud_off_rounded;
    }

    return AdminPanel(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AdminPalette.amber, size: 42),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AdminPalette.text,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AdminPalette.textDim,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              style: OutlinedButton.styleFrom(
                foregroundColor: AdminPalette.text,
                side: const BorderSide(color: AdminPalette.borderStrong),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
