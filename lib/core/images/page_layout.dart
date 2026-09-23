import 'package:flutter/foundation.dart';

import 'image_normalizer.dart';

/// Page sizes offered by Images to PDF (requirements.md 3.8), in PDF points.
enum PageSize {
  a4('A4', 595.28, 841.89),
  a5('A5', 419.53, 595.28),
  letter('Letter', 612, 792),
  legal('Legal', 612, 1008),

  /// Each page takes the shape of its own image.
  original('Original', 0, 0);

  const PageSize(this.label, this.width, this.height);

  final String label;
  final double width;
  final double height;

  bool get followsImage => this == PageSize.original;
}

enum PageOrientation {
  auto('Auto'),
  portrait('Portrait'),
  landscape('Landscape');

  const PageOrientation(this.label);
  final String label;
}

enum PageMargin {
  none('None', 0),
  small('Small', 18),
  medium('Medium', 36);

  const PageMargin(this.label, this.points);

  final String label;
  final double points;
}

enum ImageFit {
  /// The whole image is visible; the page may show margins around it.
  fit('Fit'),

  /// The image covers the page; the overflowing edges are cropped.
  fill('Fill');

  const ImageFit(this.label);
  final String label;
}

@immutable
class ImagePageOptions {
  const ImagePageOptions({
    this.size = PageSize.a4,
    this.orientation = PageOrientation.auto,
    this.margin = PageMargin.small,
    this.fit = ImageFit.fit,
    this.quality = ImageQuality.high,
  });

  final PageSize size;
  final PageOrientation orientation;
  final PageMargin margin;
  final ImageFit fit;
  final ImageQuality quality;

  ImagePageOptions copyWith({
    PageSize? size,
    PageOrientation? orientation,
    PageMargin? margin,
    ImageFit? fit,
    ImageQuality? quality,
  }) =>
      ImagePageOptions(
        size: size ?? this.size,
        orientation: orientation ?? this.orientation,
        margin: margin ?? this.margin,
        fit: fit ?? this.fit,
        quality: quality ?? this.quality,
      );
}

/// Where one image sits on its page, in PDF points.
@immutable
class PagePlacement {
  const PagePlacement({
    required this.pageWidth,
    required this.pageHeight,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double pageWidth;
  final double pageHeight;
  final double x;
  final double y;
  final double width;
  final double height;
}

/// Works out the page and the image rectangle for one image.
///
/// Pure arithmetic, kept out of the widget and the engine so the awkward cases
/// -- a panorama on A4, fill versus fit, margins bigger than the page -- can be
/// tested directly.
PagePlacement layoutImage(NormalizedImage image, ImagePageOptions options) {
  final imageIsLandscape = image.width > image.height;

  double pageWidth;
  double pageHeight;

  if (options.size.followsImage) {
    // 72 points per inch, treating the image as 72 dpi, so a page matches its
    // image exactly.
    pageWidth = image.width.toDouble();
    pageHeight = image.height.toDouble();
  } else {
    pageWidth = options.size.width;
    pageHeight = options.size.height;
    final wantsLandscape = switch (options.orientation) {
      PageOrientation.portrait => false,
      PageOrientation.landscape => true,
      PageOrientation.auto => imageIsLandscape,
    };
    if (wantsLandscape) {
      (pageWidth, pageHeight) = (pageHeight, pageWidth);
    }
  }

  // A margin can never eat the whole page.
  final maxMargin = (pageWidth < pageHeight ? pageWidth : pageHeight) / 2 - 1;
  final margin = options.margin.points.clamp(0.0, maxMargin > 0 ? maxMargin : 0.0);
  final boxWidth = pageWidth - margin * 2;
  final boxHeight = pageHeight - margin * 2;

  final imageRatio = image.aspectRatio;
  final boxRatio = boxHeight == 0 ? 1 : boxWidth / boxHeight;

  double width;
  double height;
  final coverFirst = options.fit == ImageFit.fill;
  if ((imageRatio > boxRatio) != coverFirst) {
    width = boxWidth;
    height = boxWidth / imageRatio;
  } else {
    height = boxHeight;
    width = boxHeight * imageRatio;
  }

  return PagePlacement(
    pageWidth: pageWidth,
    pageHeight: pageHeight,
    x: (pageWidth - width) / 2,
    y: (pageHeight - height) / 2,
    width: width,
    height: height,
  );
}
