import 'package:flutter/material.dart';
import '../../../shared/theme/theme_extensions.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:io' show Platform;
import 'package:eden_ai/l10n/app_localizations.dart';
import '../services/file_attachment_service.dart';
import '../../../shared/widgets/loading_states.dart';

class FileAttachmentWidget extends ConsumerWidget {
  const FileAttachmentWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attachedFiles = ref.watch(attachedFilesProvider);

    if (attachedFiles.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.sm, Spacing.md, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)!.attachments,
            style: TextStyle(
              color: context.conduitTheme.textSecondary.withValues(alpha: 0.7),
              fontSize: AppTypography.labelMedium,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: attachedFiles
                  .map(
                    (fileState) => Padding(
                      padding: const EdgeInsets.only(right: Spacing.sm),
                      child: _FileAttachmentCard(fileState: fileState),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: const Duration(milliseconds: 300));
  }
}

class _FileAttachmentCard extends ConsumerWidget {
  final FileUploadState fileState;

  const _FileAttachmentCard({required this.fileState});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: context.conduitTheme.cardBackground,
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        border: Border.all(
          color: _getBorderColor(fileState.status, context),
          width: BorderWidth.regular,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                fileState.fileIcon,
                style: const TextStyle(fontSize: AppTypography.headlineLarge),
              ),
              const Spacer(),
              _buildStatusIcon(context),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            fileState.fileName,
            style: TextStyle(
              color: context.conduitTheme.textPrimary,
              fontSize: AppTypography.labelLarge,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            fileState.formattedSize,
            style: TextStyle(
              color: context.conduitTheme.textSecondary.withValues(alpha: 0.6),
              fontSize: AppTypography.labelMedium,
            ),
          ),
          if (fileState.status == FileUploadStatus.uploading) ...[
            const SizedBox(height: Spacing.sm),
            _buildProgressBar(context),
          ],
          if (fileState.error != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(
              'Failed to upload',
              style: TextStyle(
                color: context.conduitTheme.error,
                fontSize: AppTypography.labelMedium,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusIcon(BuildContext context) {
    switch (fileState.status) {
      case FileUploadStatus.pending:
        return Icon(
          Platform.isIOS ? CupertinoIcons.clock : Icons.schedule,
          size: IconSize.sm,
          color: context.conduitTheme.iconDisabled,
        );
      case FileUploadStatus.uploading:
        return ConduitLoading.inline(
          size: IconSize.sm,
          color: context.conduitTheme.iconSecondary,
        );
      case FileUploadStatus.completed:
        return Icon(
          Platform.isIOS
              ? CupertinoIcons.checkmark_circle_fill
              : Icons.check_circle,
          size: IconSize.sm,
          color: context.conduitTheme.success,
        );
      case FileUploadStatus.failed:
        return GestureDetector(
          onTap: () {
            // Retry upload
          },
          child: Icon(
            Platform.isIOS
                ? CupertinoIcons.exclamationmark_circle_fill
                : Icons.error,
            size: IconSize.sm,
            color: context.conduitTheme.error,
          ),
        );
    }
  }

  Widget _buildProgressBar(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppBorderRadius.xs),
      child: LinearProgressIndicator(
        value: fileState.progress,
        backgroundColor: context.conduitTheme.textPrimary.withValues(
          alpha: 0.1,
        ),
        valueColor: AlwaysStoppedAnimation<Color>(
          context.conduitTheme.buttonPrimary,
        ),
        minHeight: 4,
      ),
    );
  }

  Color _getBorderColor(FileUploadStatus status, BuildContext context) {
    switch (status) {
      case FileUploadStatus.pending:
        return context.conduitTheme.textPrimary.withValues(alpha: 0.2);
      case FileUploadStatus.uploading:
        return context.conduitTheme.buttonPrimary.withValues(alpha: 0.5);
      case FileUploadStatus.completed:
        return context.conduitTheme.success.withValues(alpha: 0.3);
      case FileUploadStatus.failed:
        return context.conduitTheme.error.withValues(alpha: 0.3);
    }
  }
}

// Attachment preview for messages
class MessageAttachmentPreview extends StatelessWidget {
  final List<String> fileIds;

  const MessageAttachmentPreview({super.key, required this.fileIds});

  @override
  Widget build(BuildContext context) {
    if (fileIds.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: Spacing.sm),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: fileIds
            .map(
              (fileId) => Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: context.conduitTheme.textPrimary.withValues(
                    alpha: 0.1,
                  ),
                  borderRadius: BorderRadius.circular(AppBorderRadius.sm),
                  border: Border.all(
                    color: context.conduitTheme.textPrimary.withValues(
                      alpha: 0.2,
                    ),
                    width: BorderWidth.regular,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '📎',
                      style: TextStyle(fontSize: AppTypography.bodyLarge),
                    ),
                    const SizedBox(width: Spacing.xs),
                    Text(
                      'Attachment',
                      style: TextStyle(
                        color: context.conduitTheme.textPrimary.withValues(
                          alpha: 0.8,
                        ),
                        fontSize: AppTypography.labelLarge,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
