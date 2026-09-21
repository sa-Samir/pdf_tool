import 'package:flutter/material.dart';

import '../models/pdf_tool.dart';

/// The tool table from requirements.md 3.1, as data.
///
/// Every tool is declared here with the release it ships in, so the home screen
/// filters rather than the list being edited each phase. Aliases are the verbs
/// users search for.
abstract final class ToolCatalog {
  static const all = <PdfTool>[
    // --- Organize -----------------------------------------------------------
    PdfTool(
      id: 'merge',
      label: 'Merge',
      description: 'Combine several PDFs into one',
      icon: Icons.merge_type,
      group: ToolGroup.organize,
      release: Release.v1_0,
      tier: ToolTier.freeWithLimit,
      tierNote: 'Up to 3 files',
      aliases: ['combine', 'join', 'append', 'concat', 'together', 'add'],
    ),
    PdfTool(
      id: 'split',
      label: 'Split',
      description: 'Break a PDF into separate files',
      icon: Icons.call_split,
      group: ToolGroup.organize,
      release: Release.v1_0,
      tier: ToolTier.free,
      aliases: ['divide', 'separate', 'cut', 'break', 'chop'],
    ),
    PdfTool(
      id: 'extract',
      label: 'Extract pages',
      description: 'Pull selected pages into a new PDF',
      icon: Icons.content_copy_outlined,
      group: ToolGroup.organize,
      release: Release.v1_0,
      tier: ToolTier.free,
      aliases: ['take', 'pull', 'copy pages', 'save pages', 'pick'],
    ),
    PdfTool(
      id: 'delete_pages',
      label: 'Delete pages',
      description: 'Remove pages you do not need',
      icon: Icons.delete_outline,
      group: ToolGroup.organize,
      release: Release.v1_0,
      tier: ToolTier.free,
      aliases: ['remove', 'erase', 'drop', 'discard'],
    ),
    PdfTool(
      id: 'rotate',
      label: 'Rotate pages',
      description: 'Turn pages the right way up',
      icon: Icons.rotate_90_degrees_cw_outlined,
      group: ToolGroup.organize,
      release: Release.v1_0,
      tier: ToolTier.free,
      aliases: ['turn', 'sideways', 'upside down', 'orientation', 'landscape'],
    ),
    PdfTool(
      id: 'reorder',
      label: 'Reorder pages',
      description: 'Drag pages into a new order',
      icon: Icons.swap_vert,
      group: ToolGroup.organize,
      release: Release.v1_0,
      tier: ToolTier.free,
      aliases: ['rearrange', 'move', 'sort', 'organise', 'organize', 'shuffle'],
    ),
    PdfTool(
      id: 'duplicate',
      label: 'Duplicate pages',
      description: 'Copy a page within the document',
      icon: Icons.copy_all_outlined,
      group: ToolGroup.organize,
      release: Release.v1_0,
      tier: ToolTier.free,
      aliases: ['repeat', 'clone', 'copy'],
    ),

    // --- Convert ------------------------------------------------------------
    PdfTool(
      id: 'images_to_pdf',
      label: 'Images to PDF',
      description: 'Turn photos into a single PDF',
      icon: Icons.image_outlined,
      group: ToolGroup.convert,
      release: Release.v1_0,
      tier: ToolTier.freeWithLimit,
      tierNote: 'Up to 10 images',
      aliases: ['photo', 'picture', 'jpg', 'jpeg', 'png', 'heic', 'camera roll'],
    ),
    PdfTool(
      id: 'pdf_to_images',
      label: 'PDF to images',
      description: 'Save pages as JPG or PNG',
      icon: Icons.collections_outlined,
      group: ToolGroup.convert,
      release: Release.v1_0,
      tier: ToolTier.freeWithLimit,
      tierNote: 'Up to 150 DPI',
      aliases: ['export', 'jpg', 'png', 'picture', 'photo', 'screenshot'],
    ),
    PdfTool(
      id: 'ocr',
      label: 'Make searchable',
      description: 'Recognise text in a scanned PDF',
      icon: Icons.text_snippet_outlined,
      group: ToolGroup.convert,
      release: Release.v1_3,
      tier: ToolTier.premium,
      aliases: ['ocr', 'searchable', 'recognise', 'recognize', 'text'],
    ),

    // --- Optimize -----------------------------------------------------------
    PdfTool(
      id: 'compress',
      label: 'Compress',
      description: 'Make a large PDF smaller',
      icon: Icons.compress,
      group: ToolGroup.optimize,
      release: Release.v1_0,
      tier: ToolTier.premium,
      aliases: ['shrink', 'reduce', 'smaller', 'size', 'optimise', 'optimize',
        'email', 'too big'],
    ),

    // --- Capture ------------------------------------------------------------
    PdfTool(
      id: 'scan',
      label: 'Scan document',
      description: 'Capture paper with the camera',
      icon: Icons.document_scanner_outlined,
      group: ToolGroup.capture,
      release: Release.v1_1,
      tier: ToolTier.freeWithLimit,
      tierNote: 'Up to 3 pages',
      aliases: ['camera', 'photo', 'paper', 'receipt', 'scanner'],
    ),

    // --- Edit & Sign --------------------------------------------------------
    PdfTool(
      id: 'signature',
      label: 'Signature',
      description: 'Sign a document by hand',
      icon: Icons.draw_outlined,
      group: ToolGroup.editSign,
      release: Release.v1_1,
      tier: ToolTier.premium,
      aliases: ['sign', 'autograph', 'initials'],
    ),
    PdfTool(
      id: 'annotate',
      label: 'Annotate',
      description: 'Highlight, draw and mark up',
      icon: Icons.brush_outlined,
      group: ToolGroup.editSign,
      release: Release.v1_2,
      tier: ToolTier.premium,
      aliases: ['highlight', 'draw', 'markup', 'comment', 'note', 'underline'],
    ),
    PdfTool(
      id: 'add_text',
      label: 'Add text',
      description: 'Type onto a page',
      icon: Icons.text_fields,
      group: ToolGroup.editSign,
      release: Release.v1_2,
      tier: ToolTier.premium,
      aliases: ['write', 'type', 'fill', 'form', 'edit'],
    ),
    PdfTool(
      id: 'watermark',
      label: 'Watermark',
      description: 'Stamp text or an image over pages',
      icon: Icons.branding_watermark_outlined,
      group: ToolGroup.editSign,
      release: Release.v1_2,
      tier: ToolTier.premium,
      aliases: ['stamp', 'draft', 'confidential', 'logo', 'brand'],
    ),

    // --- Secure -------------------------------------------------------------
    PdfTool(
      id: 'protect',
      label: 'Protect',
      description: 'Add a password to a PDF',
      icon: Icons.lock_outline,
      group: ToolGroup.secure,
      release: Release.v1_3,
      tier: ToolTier.premium,
      aliases: ['password', 'encrypt', 'lock', 'secure', 'private'],
    ),
    PdfTool(
      id: 'unlock',
      label: 'Unlock',
      description: 'Remove a password you know',
      icon: Icons.lock_open_outlined,
      group: ToolGroup.secure,
      release: Release.v1_3,
      tier: ToolTier.premium,
      aliases: ['password', 'decrypt', 'remove password', 'open'],
    ),
  ];

  /// Tools this build actually ships, in group order.
  static List<PdfTool> get shipped =>
      all.where((t) => t.isShipped).toList(growable: false);

  /// Shipped tools matching [query], grouped, preserving declaration order.
  /// Groups with no matches are omitted.
  static Map<ToolGroup, List<PdfTool>> grouped({String query = ''}) {
    final result = <ToolGroup, List<PdfTool>>{};
    for (final group in ToolGroup.values) {
      final tools = shipped
          .where((t) => t.group == group && t.matches(query))
          .toList(growable: false);
      if (tools.isNotEmpty) result[group] = tools;
    }
    return result;
  }
}
