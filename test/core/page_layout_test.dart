import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_toolbox/core/images/image_normalizer.dart';
import 'package:pdf_toolbox/core/images/page_layout.dart';

void main() {
  NormalizedImage image(int width, int height) => NormalizedImage(
        file: File('/memory/x.jpg'),
        width: width,
        height: height,
      );

  final portrait = image(1200, 1600);
  final landscape = image(1600, 1200);
  final panorama = image(4000, 800);

  group('page size', () {
    test('A4 portrait for a portrait photo on auto', () {
      final placement = layoutImage(
        portrait,
        const ImagePageOptions(margin: PageMargin.none),
      );
      expect(placement.pageWidth, closeTo(595.28, 0.01));
      expect(placement.pageHeight, closeTo(841.89, 0.01));
    });

    test('auto turns the page for a landscape photo', () {
      final placement = layoutImage(
        landscape,
        const ImagePageOptions(margin: PageMargin.none),
      );
      expect(placement.pageWidth, closeTo(841.89, 0.01));
      expect(placement.pageHeight, closeTo(595.28, 0.01));
    });

    test('an explicit orientation overrides the image', () {
      final placement = layoutImage(
        landscape,
        const ImagePageOptions(orientation: PageOrientation.portrait),
      );
      expect(placement.pageWidth, lessThan(placement.pageHeight));
    });

    test('original size gives the page the image shape', () {
      final placement = layoutImage(
        portrait,
        const ImagePageOptions(size: PageSize.original, margin: PageMargin.none),
      );
      expect(placement.pageWidth, 1200);
      expect(placement.pageHeight, 1600);
      expect(placement.width, 1200);
      expect(placement.height, 1600);
    });
  });

  group('fit', () {
    test('the whole image is inside the page', () {
      final placement = layoutImage(
        panorama,
        const ImagePageOptions(margin: PageMargin.none),
      );
      expect(placement.width, lessThanOrEqualTo(placement.pageWidth + 0.01));
      expect(placement.height, lessThanOrEqualTo(placement.pageHeight + 0.01));
    });

    test('the aspect ratio is preserved', () {
      final placement = layoutImage(portrait, const ImagePageOptions());
      expect(
        placement.width / placement.height,
        closeTo(portrait.aspectRatio, 0.001),
      );
    });

    test('the image is centred', () {
      final placement = layoutImage(panorama, const ImagePageOptions());
      expect(
        placement.x * 2 + placement.width,
        closeTo(placement.pageWidth, 0.01),
      );
      expect(
        placement.y * 2 + placement.height,
        closeTo(placement.pageHeight, 0.01),
      );
    });
  });

  group('fill', () {
    test('the image covers the page, overflowing rather than leaving gaps', () {
      final placement = layoutImage(
        panorama,
        const ImagePageOptions(fit: ImageFit.fill, margin: PageMargin.none),
      );
      expect(placement.width, greaterThanOrEqualTo(placement.pageWidth - 0.01));
      expect(
        placement.height,
        greaterThanOrEqualTo(placement.pageHeight - 0.01),
      );
    });

    test('fill still preserves the aspect ratio', () {
      final placement = layoutImage(
        panorama,
        const ImagePageOptions(fit: ImageFit.fill),
      );
      expect(
        placement.width / placement.height,
        closeTo(panorama.aspectRatio, 0.001),
      );
    });
  });

  group('margins', () {
    test('a margin insets the image on both sides', () {
      final none = layoutImage(
        portrait,
        const ImagePageOptions(margin: PageMargin.none),
      );
      final medium = layoutImage(
        portrait,
        const ImagePageOptions(margin: PageMargin.medium),
      );
      expect(medium.width, lessThan(none.width));
      expect(medium.x, greaterThan(none.x));
    });

    test('a margin cannot consume the whole page', () {
      // An A5 page with a margin far larger than itself.
      final placement = layoutImage(
        image(100, 100),
        const ImagePageOptions(size: PageSize.original, margin: PageMargin.medium),
      );
      expect(placement.width, greaterThan(0));
      expect(placement.height, greaterThan(0));
    });
  });

  test('a square image on a square page fills it exactly', () {
    final placement = layoutImage(
      image(500, 500),
      const ImagePageOptions(size: PageSize.original, margin: PageMargin.none),
    );
    expect(placement.x, 0);
    expect(placement.y, 0);
    expect(placement.width, 500);
    expect(placement.height, 500);
  });
}
