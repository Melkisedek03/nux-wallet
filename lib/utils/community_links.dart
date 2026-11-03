/// Tautan komunitas Nusacoin untuk kartu Komunitas di tab Profil.
///
/// Data murni (label tampil + URL tujuan) supaya bisa dites dan
/// tidak tercecer sebagai string liar di widget. Ketukan pada
/// tautan dibuka di browser eksternal (url_launcher).
library;

/// Satu tautan komunitas: [label] yang dibaca pengguna dan [url]
/// lengkap yang dibuka di browser eksternal.
class CommunityLink {
  final String label;
  final String url;

  const CommunityLink({required this.label, required this.url});
}

/// Website komunitas Nusacoin.
const communityWebsiteLinks = <CommunityLink>[
  CommunityLink(label: 'nusacoin.org', url: 'https://nusacoin.org'),
  CommunityLink(
      label: 'www.nusachain.org', url: 'https://www.nusachain.org'),
];

/// Grup Telegram komunitas Nusacoin.
const communityTelegramLinks = <CommunityLink>[
  CommunityLink(label: 't.me/NusacoinX11', url: 'https://t.me/NusacoinX11'),
];
