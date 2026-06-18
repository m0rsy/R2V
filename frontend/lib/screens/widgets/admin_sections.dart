import 'package:flutter/material.dart';

import '../../api/admin_service.dart';
import '../../api/freelance_service.dart';
import '../../api/r2v_api.dart';
import 'admin_console_widgets.dart';

/// Two-column responsive panel row used by several sections.
class _PanelRow extends StatelessWidget {
  const _PanelRow({required this.primary, required this.secondary, this.primaryFlex = 3, this.secondaryFlex = 2});

  final Widget primary;
  final Widget secondary;
  final int primaryFlex;
  final int secondaryFlex;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 880) {
          return Column(
            children: [primary, const SizedBox(height: 16), secondary],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: primaryFlex, child: primary),
            const SizedBox(width: 16),
            Expanded(flex: secondaryFlex, child: secondary),
          ],
        );
      },
    );
  }
}

Widget _avatarTile({
  required IconData icon,
  required Color color,
  required String title,
  required String subtitle,
  Widget? trailing,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(0.16),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AdminPalette.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AdminPalette.textDim,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 10), trailing],
      ],
    ),
  );
}

String _shortId(String id) => id.length > 8 ? '${id.substring(0, 8)}…' : id;

Color _statusColor(String status) {
  switch (status.toLowerCase()) {
    case 'published':
    case 'completed':
    case 'done':
    case 'connected':
      return AdminPalette.green;
    case 'failed':
    case 'error':
    case 'suspended':
      return AdminPalette.red;
    case 'processing':
    case 'queued':
    case 'created':
      return AdminPalette.blue;
    default:
      return AdminPalette.amber;
  }
}

// ===========================================================================
// System Overview
// ===========================================================================

class AdminOverviewSection extends StatelessWidget {
  const AdminOverviewSection({super.key, required this.refreshTick});

  final int refreshTick;

  @override
  Widget build(BuildContext context) {
    return AdminSectionLoader<AdminSummary>(
      refreshTick: refreshTick,
      loader: r2vAdmin.summary,
      builder: (context, data) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdminMetricGrid(
              cards: [
                AdminMetricCard(
                  label: 'Total AI Generations',
                  value: '${data.aiJobs}',
                  icon: Icons.auto_awesome_rounded,
                  color: AdminPalette.violet,
                ),
                AdminMetricCard(
                  label: 'Published Assets',
                  value: '${data.publishedAssets}',
                  icon: Icons.view_in_ar_rounded,
                  color: AdminPalette.blue,
                ),
                AdminMetricCard(
                  label: 'Marketplace Sales',
                  value: '${data.purchases}',
                  icon: Icons.payments_rounded,
                  color: AdminPalette.green,
                ),
                AdminMetricCard(
                  label: 'Total Users',
                  value: '${data.users}',
                  icon: Icons.group_rounded,
                  color: AdminPalette.amber,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _PanelRow(
              primary: AdminPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AdminPanelHeader(
                      icon: Icons.auto_awesome_rounded,
                      title: 'Recent Assets',
                    ),
                    const SizedBox(height: 14),
                    if (data.recentAssets.isEmpty)
                      const AdminEmptyState(
                        icon: Icons.view_in_ar_outlined,
                        title: 'No assets yet',
                        message:
                            'Generated and published assets will appear here.',
                      )
                    else
                      ...data.recentAssets.map(
                        (asset) => _avatarTile(
                          icon: Icons.category_rounded,
                          color: AdminPalette.violet,
                          title: asset.title.isEmpty ? 'Untitled' : asset.title,
                          subtitle: 'Creator ${_shortId(asset.creatorId)}',
                          trailing: AdminStatusPill(
                            label: asset.visibility,
                            color: _statusColor(asset.visibility),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              secondary: AdminPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AdminPanelHeader(
                      icon: Icons.insights_rounded,
                      title: 'Platform Activity',
                    ),
                    const SizedBox(height: 14),
                    _statRow('Active users', '${data.activeUsers}'),
                    _statRow('Draft assets', '${data.draftAssets}'),
                    _statRow('Downloads', '${data.downloads}'),
                    _statRow('Scan jobs', '${data.scanJobs}'),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AdminPalette.textDim, fontSize: 13)),
          Text(
            value,
            style: const TextStyle(
              color: AdminPalette.text,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// AI Model Management
// ===========================================================================

class AdminAiSection extends StatelessWidget {
  const AdminAiSection({super.key, required this.refreshTick});

  final int refreshTick;

  @override
  Widget build(BuildContext context) {
    return AdminSectionLoader<AdminJobs>(
      refreshTick: refreshTick,
      loader: r2vAdmin.jobs,
      builder: (context, data) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdminMetricGrid(
              cards: [
                AdminMetricCard(
                  label: 'Global Queue',
                  value: '${data.queue}',
                  icon: Icons.layers_rounded,
                  color: AdminPalette.violet,
                ),
                AdminMetricCard(
                  label: 'Processing',
                  value: '${data.processing}',
                  icon: Icons.timelapse_rounded,
                  color: AdminPalette.blue,
                ),
                AdminMetricCard(
                  label: 'Failed Jobs',
                  value: '${data.failed}',
                  icon: Icons.error_outline_rounded,
                  color: AdminPalette.red,
                ),
                AdminMetricCard(
                  label: 'Avg Progress',
                  value: '${data.averageProgress}%',
                  icon: Icons.speed_rounded,
                  color: AdminPalette.amber,
                ),
              ],
            ),
            const SizedBox(height: 16),
            AdminPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AdminPanelHeader(
                    icon: Icons.memory_rounded,
                    title: 'Generation Jobs',
                  ),
                  const SizedBox(height: 14),
                  if (data.recent.isEmpty)
                    const AdminEmptyState(
                      icon: Icons.precision_manufacturing_outlined,
                      title: 'No active engine jobs',
                      message:
                          'AI and scan jobs, queue status, and progress will appear here.',
                    )
                  else
                    ...data.recent.map(
                      (job) => _avatarTile(
                        icon: job.type == 'scan'
                            ? Icons.camera_alt_rounded
                            : Icons.auto_awesome_rounded,
                        color: job.type == 'scan'
                            ? AdminPalette.blue
                            : AdminPalette.violet,
                        title: '${job.type.toUpperCase()} • ${_shortId(job.id)}',
                        subtitle: 'Progress ${job.progress}%',
                        trailing: AdminStatusPill(
                          label: job.status,
                          color: _statusColor(job.status),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ===========================================================================
// Marketplace Console
// ===========================================================================

class AdminMarketplaceSection extends StatelessWidget {
  const AdminMarketplaceSection({super.key, required this.refreshTick});

  final int refreshTick;

  @override
  Widget build(BuildContext context) {
    return AdminSectionLoader<AdminMarketplace>(
      refreshTick: refreshTick,
      loader: r2vAdmin.marketplace,
      builder: (context, data) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdminMetricGrid(
              cards: [
                AdminMetricCard(
                  label: 'Pending Review',
                  value: '${data.pendingReview}',
                  icon: Icons.fact_check_rounded,
                  color: AdminPalette.amber,
                ),
                AdminMetricCard(
                  label: 'Flagged Assets',
                  value: '${data.flagged}',
                  icon: Icons.flag_rounded,
                  color: AdminPalette.red,
                ),
                AdminMetricCard(
                  label: 'Approved Today',
                  value: '${data.approvedToday}',
                  icon: Icons.verified_rounded,
                  color: AdminPalette.green,
                ),
                AdminMetricCard(
                  label: 'Downloads',
                  value: '${data.downloads}',
                  icon: Icons.download_rounded,
                  color: AdminPalette.blue,
                ),
              ],
            ),
            const SizedBox(height: 16),
            AdminPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AdminPanelHeader(
                    icon: Icons.storefront_rounded,
                    title: 'Asset Moderation',
                  ),
                  const SizedBox(height: 14),
                  if (data.assets.isEmpty)
                    const AdminEmptyState(
                      icon: Icons.view_in_ar_outlined,
                      title: 'No assets to review',
                      message:
                          'Pending, approved, and flagged assets will appear here from the marketplace.',
                    )
                  else
                    ...data.assets.map(
                      (asset) => _avatarTile(
                        icon: Icons.category_rounded,
                        color: AdminPalette.violet,
                        title: asset.title.isEmpty ? 'Untitled' : asset.title,
                        subtitle:
                            '${asset.category} • ${asset.isPaid ? '${asset.currency.toUpperCase()} ${asset.price}' : 'Free'}',
                        trailing: AdminStatusPill(
                          label: asset.visibility,
                          color: _statusColor(asset.visibility),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ===========================================================================
// Directory (Users)
// ===========================================================================

class AdminDirectorySection extends StatelessWidget {
  const AdminDirectorySection({super.key, required this.refreshTick});

  final int refreshTick;

  @override
  Widget build(BuildContext context) {
    return AdminSectionLoader<AdminUsers>(
      refreshTick: refreshTick,
      loader: r2vAdmin.users,
      builder: (context, data) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdminMetricGrid(
              cards: [
                AdminMetricCard(
                  label: 'Total Users',
                  value: '${data.total}',
                  icon: Icons.group_rounded,
                  color: AdminPalette.violet,
                ),
                AdminMetricCard(
                  label: 'Active Creators',
                  value: '${data.creators}',
                  icon: Icons.brush_rounded,
                  color: AdminPalette.blue,
                ),
                AdminMetricCard(
                  label: 'Freelancers',
                  value: '${data.freelancers}',
                  icon: Icons.work_outline_rounded,
                  color: AdminPalette.amber,
                ),
                AdminMetricCard(
                  label: 'Suspended',
                  value: '${data.suspended}',
                  icon: Icons.block_rounded,
                  color: AdminPalette.red,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _PanelRow(
              primary: AdminPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AdminPanelHeader(
                      icon: Icons.groups_rounded,
                      title: 'Global Directory',
                    ),
                    const SizedBox(height: 14),
                    if (data.users.isEmpty)
                      const AdminEmptyState(
                        icon: Icons.person_outline_rounded,
                        title: 'No users yet',
                        message:
                            'Registered users, roles, and account status will appear here.',
                      )
                    else
                      ...data.users.map(
                        (user) => _avatarTile(
                          icon: Icons.person_rounded,
                          color: user.isActive
                              ? AdminPalette.blue
                              : AdminPalette.red,
                          title: user.username?.isNotEmpty == true
                              ? user.username!
                              : user.email,
                          subtitle: user.email,
                          trailing: AdminStatusPill(
                            label: user.isActive ? user.role : 'suspended',
                            color: user.isActive
                                ? _statusColor(user.role)
                                : AdminPalette.red,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              secondary: const AdminPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AdminPanelHeader(
                      icon: Icons.verified_user_rounded,
                      title: 'Verification Requests',
                    ),
                    SizedBox(height: 14),
                    AdminEmptyState(
                      icon: Icons.workspace_premium_outlined,
                      title: 'No pending requests',
                      message:
                          'Creator and freelancer verification requests will appear here.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ===========================================================================
// Freelancers
// ===========================================================================

class AdminFreelancersSection extends StatelessWidget {
  const AdminFreelancersSection({super.key, required this.refreshTick});

  final int refreshTick;

  @override
  Widget build(BuildContext context) {
    return AdminSectionLoader<AdminFreelancers>(
      refreshTick: refreshTick,
      loader: r2vAdmin.freelancers,
      builder: (context, data) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdminMetricGrid(
              cards: [
                AdminMetricCard(
                  label: 'Total Freelancers',
                  value: '${data.total}',
                  icon: Icons.work_outline_rounded,
                  color: AdminPalette.violet,
                ),
                AdminMetricCard(
                  label: 'Active',
                  value: '${data.active}',
                  icon: Icons.verified_user_rounded,
                  color: AdminPalette.green,
                ),
                AdminMetricCard(
                  label: 'Featured',
                  value: '${data.featured}',
                  icon: Icons.star_rounded,
                  color: AdminPalette.amber,
                ),
              ],
            ),
            const SizedBox(height: 16),
            AdminPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AdminPanelHeader(
                    icon: Icons.people_alt_rounded,
                    title: 'Freelancer Network',
                  ),
                  const SizedBox(height: 14),
                  if (data.freelancers.isEmpty)
                    const AdminEmptyState(
                      icon: Icons.badge_outlined,
                      title: 'No freelancers found yet',
                      message:
                          'Approved freelancer accounts will be listed here once they join.',
                    )
                  else
                    ...data.freelancers.map(
                      (FreelanceProfile f) => _avatarTile(
                        icon: Icons.person_rounded,
                        color: AdminPalette.violet,
                        title: f.displayName.isEmpty ? f.username : f.displayName,
                        subtitle: f.role,
                        trailing: f.featured
                            ? const AdminStatusPill(
                                label: 'featured',
                                color: AdminPalette.amber,
                              )
                            : null,
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ===========================================================================
// Moderation Hub
// ===========================================================================

class AdminModerationSection extends StatelessWidget {
  const AdminModerationSection({super.key, required this.refreshTick});

  final int refreshTick;

  @override
  Widget build(BuildContext context) {
    return AdminSectionLoader<AdminModeration>(
      refreshTick: refreshTick,
      loader: r2vAdmin.moderation,
      builder: (context, data) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdminMetricGrid(
              cards: [
                AdminMetricCard(
                  label: 'Open Reports',
                  value: '${data.openReports}',
                  icon: Icons.flag_rounded,
                  color: AdminPalette.red,
                ),
                AdminMetricCard(
                  label: 'Appeals',
                  value: '${data.appeals}',
                  icon: Icons.gavel_rounded,
                  color: AdminPalette.amber,
                ),
                AdminMetricCard(
                  label: 'Flagged Users',
                  value: '${data.flaggedUsers}',
                  icon: Icons.person_off_rounded,
                  color: AdminPalette.violet,
                ),
                AdminMetricCard(
                  label: 'Flagged Assets',
                  value: '${data.flaggedAssets}',
                  icon: Icons.inventory_2_rounded,
                  color: AdminPalette.blue,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _PanelRow(
              primaryFlex: 2,
              secondaryFlex: 3,
              primary: const AdminPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AdminPanelHeader(
                      icon: Icons.person_search_rounded,
                      title: 'Target Entity Review',
                    ),
                    SizedBox(height: 14),
                    AdminEmptyState(
                      icon: Icons.manage_search_rounded,
                      title: 'No selected entity',
                      message:
                          'Reported user or asset profile and actions will appear here.',
                    ),
                  ],
                ),
              ),
              secondary: AdminPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AdminPanelHeader(
                      icon: Icons.rule_rounded,
                      title: 'Violation Matrix',
                    ),
                    const SizedBox(height: 14),
                    if (data.violations.isEmpty)
                      const AdminEmptyState(
                        icon: Icons.shield_outlined,
                        title: 'No violations recorded',
                        message:
                            'TOS violations, automated flags, and strike history will appear here.',
                      )
                    else
                      ...data.violations.map(
                        (v) => _avatarTile(
                          icon: Icons.warning_amber_rounded,
                          color: AdminPalette.red,
                          title: v['title']?.toString() ?? 'Violation',
                          subtitle: v['detail']?.toString() ?? '',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ===========================================================================
// System Health
// ===========================================================================

class AdminSystemSection extends StatelessWidget {
  const AdminSystemSection({super.key, required this.refreshTick});

  final int refreshTick;

  @override
  Widget build(BuildContext context) {
    return AdminSectionLoader<AdminSystem>(
      refreshTick: refreshTick,
      loader: r2vAdmin.system,
      builder: (context, data) {
        final db = data.database;
        final redis = data.redis;
        final celery = data.celery;
        final storage = data.storage;
        final ai = data.aiPipeline;
        final modal = (ai['modal_endpoint'] is Map)
            ? (ai['modal_endpoint'] as Map).cast<String, dynamic>()
            : const <String, dynamic>{};

        final backendStatus = (data.backendInfo['status'] ?? data.backend)
            .toString();
        final dbStatus = (db['status'] ?? 'unknown').toString();
        final redisStatus = (redis['status'] ?? 'unknown').toString();
        final celeryStatus = (celery['status'] ?? 'unknown').toString();
        final storageStatus = (storage['status'] ?? 'unknown').toString();
        final modalStatus = (modal['status'] ?? 'unknown').toString();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdminMetricGrid(
              cards: [
                AdminMetricCard(
                  label: 'Backend API',
                  value: backendStatus == 'connected'
                      ? 'Connected · up ${_uptime(data.backendInfo['uptime_seconds'])}'
                      : _statusLabel(backendStatus),
                  icon: Icons.cloud_done_rounded,
                  color: _statusColor(backendStatus),
                ),
                AdminMetricCard(
                  label: 'Database',
                  value:
                      '${_statusLabel(dbStatus)}${_latency(db['latency_ms'])}',
                  icon: Icons.storage_rounded,
                  color: _statusColor(dbStatus),
                ),
                AdminMetricCard(
                  label: 'Redis / Queue',
                  value:
                      'Queue ${redis['queue_size'] ?? data.queueSize}${_latency(redis['latency_ms'])}',
                  icon: Icons.layers_rounded,
                  color: _statusColor(redisStatus),
                ),
                AdminMetricCard(
                  label: 'Celery Worker',
                  value: celeryStatus == 'connected'
                      ? '${celery['workers_online'] ?? 0} online · ${celery['active_tasks'] ?? 0} active'
                      : _statusLabel(celeryStatus),
                  icon: Icons.memory_rounded,
                  color: _statusColor(celeryStatus),
                ),
                AdminMetricCard(
                  label: 'Storage Used',
                  value: (storage['used_label'] ?? data.storageUsed ?? '—')
                      .toString(),
                  icon: Icons.sd_storage_rounded,
                  color: _statusColor(storageStatus),
                ),
                AdminMetricCard(
                  label: 'AI Pipeline',
                  value:
                      '${_statusLabel(modalStatus)}${_latency(modal['latency_ms'])}',
                  icon: Icons.developer_board_rounded,
                  color: _statusColor(modalStatus),
                ),
              ],
            ),
            const SizedBox(height: 16),
            AdminPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AdminPanelHeader(
                    icon: Icons.account_tree_rounded,
                    title: 'AI & Service Configuration',
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Configured means the required environment/config is present. '
                    'Reachable means the service responded to a lightweight health check.',
                    style: TextStyle(
                      color: AdminPalette.textDim,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _pipeRow('AI Generation Endpoint', modalStatus,
                      description:
                          'Modal endpoint that runs image and 3D generation.'),
                  _pipeRow('Stable Diffusion image generation',
                      (ai['stable_diffusion'] is Map)
                          ? ((ai['stable_diffusion'] as Map)['status'] ?? 'unknown')
                              .toString()
                          : 'unknown'),
                  _pipeRow('Hunyuan3D mesh generation',
                      (ai['hunyuan3d'] is Map)
                          ? ((ai['hunyuan3d'] as Map)['status'] ?? 'unknown')
                              .toString()
                          : 'unknown'),
                  _pipeRow('Gemini multi-view generation',
                      (ai['gemini'] is Map)
                          ? ((ai['gemini'] as Map)['status'] ?? 'unknown')
                              .toString()
                          : 'unknown'),
                  _pipeRow(
                    'Marketplace moderation',
                    (data.moderation['status'] ?? 'not_configured').toString(),
                    labelOverride: 'Not enabled',
                    neutral: true,
                    description:
                        'Optional — marketplace uploads are currently managed '
                        'without automated moderation.',
                    tooltip: 'Not enabled = optional feature not active',
                  ),
                ],
              ),
            ),
            if (_realWarnings(data.warnings).isNotEmpty) ...[
              const SizedBox(height: 16),
              AdminPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AdminPanelHeader(
                      icon: Icons.warning_amber_rounded,
                      title: 'Warnings',
                    ),
                    const SizedBox(height: 8),
                    ..._realWarnings(data.warnings).map(
                      (w) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.circle,
                                size: 7, color: AdminPalette.amber),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                w,
                                style: const TextStyle(
                                  color: AdminPalette.textDim,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.schedule_rounded,
                    size: 14, color: AdminPalette.textDim),
                const SizedBox(width: 6),
                Text(
                  'Last refreshed: ${_refreshedAt(data.timestamp)}',
                  style: const TextStyle(
                    color: AdminPalette.textDim,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  // Optional services (e.g. moderation) that aren't required shouldn't be shown
  // as a scary warning — drop them from the Warnings panel.
  static List<String> _realWarnings(List<String> warnings) => warnings
      .where((w) => !w.toLowerCase().contains('moderation'))
      .toList();

  static Widget _pipeRow(
    String name,
    String status, {
    String? labelOverride,
    String? description,
    String? tooltip,
    bool neutral = false,
  }) {
    final pill = AdminStatusPill(
      label: labelOverride ?? _statusLabel(status),
      // Optional/disabled services use a neutral grey badge, never warning.
      color: neutral ? AdminPalette.textDim : _statusColor(status),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: AdminPalette.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: const TextStyle(
                      color: AdminPalette.textDim,
                      fontSize: 11.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Tooltip(
            message: tooltip ?? _statusTooltip(status),
            child: pill,
          ),
        ],
      ),
    );
  }

  static String _statusTooltip(String status) {
    switch (status) {
      case 'reachable':
        return 'Reachable = endpoint responded to a health check';
      case 'unreachable':
        return 'Unreachable = endpoint did not respond';
      case 'configured':
        return 'Configured = required env/config exists';
      case 'connected':
        return 'Connected = service is responding';
      case 'degraded':
        return 'Degraded = responding but not fully healthy';
      case 'down':
        return 'Down = service is not responding';
      case 'not_configured':
        return 'Not configured = required env/config is missing';
      default:
        return 'Status unknown';
    }
  }

  // green = healthy, yellow = degraded/warning, red = down, grey = unknown/n-c.
  static Color _statusColor(String status) {
    switch (status) {
      case 'connected':
      case 'configured':
      case 'reachable':
        return AdminPalette.green;
      case 'degraded':
        return AdminPalette.amber;
      case 'down':
      case 'unreachable':
        return AdminPalette.red;
      case 'not_configured':
      case 'unknown':
      default:
        return AdminPalette.textDim;
    }
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'connected':
        return 'Connected';
      case 'configured':
        return 'Configured';
      case 'reachable':
        return 'Reachable';
      case 'unreachable':
        return 'Unreachable';
      case 'degraded':
        return 'Degraded';
      case 'down':
        return 'Down';
      case 'not_configured':
        return 'Not configured';
      case 'unknown':
        return 'Unknown';
      default:
        return status;
    }
  }

  static String _latency(dynamic ms) {
    if (ms == null) return '';
    final n = (ms is num) ? ms : num.tryParse(ms.toString());
    if (n == null) return '';
    return ' · ${n.toStringAsFixed(n >= 10 ? 0 : 1)}ms';
  }

  static String _uptime(dynamic seconds) {
    final s = (seconds is num) ? seconds.toInt() : int.tryParse('${seconds ?? 0}') ?? 0;
    if (s < 60) return '${s}s';
    final m = s ~/ 60;
    if (m < 60) return '${m}m';
    final h = m ~/ 60;
    if (h < 24) return '${h}h ${m % 60}m';
    return '${h ~/ 24}d ${h % 24}h';
  }

  static String _refreshedAt(String? iso) {
    if (iso == null) return 'just now';
    final t = DateTime.tryParse(iso)?.toLocal();
    if (t == null) return 'just now';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}

// ===========================================================================
// Settings
// ===========================================================================

class AdminSettingsSection extends StatelessWidget {
  const AdminSettingsSection({super.key, required this.refreshTick});

  final int refreshTick;

  @override
  Widget build(BuildContext context) {
    return AdminSectionLoader<AdminSystem>(
      refreshTick: refreshTick,
      loader: r2vAdmin.system,
      builder: (context, data) {
        return AdminPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AdminPanelHeader(
                icon: Icons.settings_rounded,
                title: 'Console Settings',
              ),
              const SizedBox(height: 6),
              const Text(
                'Read-only environment information for this admin console.',
                style: TextStyle(color: AdminPalette.textDim, fontSize: 12.5),
              ),
              const SizedBox(height: 16),
              _settingRow('Environment', data.env.isEmpty ? '—' : data.env),
              _settingRow('Backend status', data.backend),
              _settingRow('GPU status', data.gpuStatus),
              _settingRow('Active queue', '${data.queueSize}'),
            ],
          ),
        );
      },
    );
  }

  static Widget _settingRow(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminPalette.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AdminPalette.textDim, fontSize: 13)),
          Text(
            value,
            style: const TextStyle(
              color: AdminPalette.text,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
