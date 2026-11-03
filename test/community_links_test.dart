import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/utils/community_links.dart';

void main() {
  test('tautan website komunitas persis seperti yang diminta', () {
    expect(communityWebsiteLinks, hasLength(2));
    expect(communityWebsiteLinks[0].label, 'nusacoin.org');
    expect(communityWebsiteLinks[0].url, 'https://nusacoin.org');
    expect(communityWebsiteLinks[1].label, 'www.nusachain.org');
    expect(communityWebsiteLinks[1].url, 'https://www.nusachain.org');
  });

  test('tautan grup Telegram komunitas persis seperti yang diminta', () {
    expect(communityTelegramLinks, hasLength(1));
    expect(communityTelegramLinks[0].label, 't.me/NusacoinX11');
    expect(communityTelegramLinks[0].url, 'https://t.me/NusacoinX11');
  });

  test('semua tautan komunitas memakai skema https', () {
    for (final link in [...communityWebsiteLinks, ...communityTelegramLinks]) {
      expect(Uri.parse(link.url).scheme, 'https', reason: link.url);
    }
  });
}
