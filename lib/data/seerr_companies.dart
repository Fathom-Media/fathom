/// A studio or network tile on the Discover home, matching the curated lists
/// the Jellyseerr web app uses. The logo images are TMDB-hosted (a duotone
/// filter baked into the URL), so nothing is bundled locally.
class SeerrCompany {
  final String name;
  final String imageUrl; // TMDB duotone logo
  final String kind; // 'studio' (movies) | 'network' (tv)
  final int id; // TMDB company / network id

  const SeerrCompany({
    required this.name,
    required this.imageUrl,
    required this.kind,
    required this.id,
  });

  String get mediaType => kind == 'network' ? 'tv' : 'movie';
}

const _duotone =
    'https://image.tmdb.org/t/p/w780_filter(duotone,ffffff,bababa)';

/// Movie studios, in Jellyseerr's order.
const kSeerrStudios = <SeerrCompany>[
  SeerrCompany(
      name: 'Disney',
      imageUrl: '$_duotone/wdrCwmRnLFJhEoH8GSfymY85KHT.png',
      kind: 'studio',
      id: 2),
  SeerrCompany(
      name: '20th Century Studios',
      imageUrl: '$_duotone/h0rjX5vjW5r8yEnUBStFarjcLT4.png',
      kind: 'studio',
      id: 127928),
  SeerrCompany(
      name: 'Sony Pictures',
      imageUrl: '$_duotone/GagSvqWlyPdkFHMfQ3pNq6ix9P.png',
      kind: 'studio',
      id: 34),
  SeerrCompany(
      name: 'Warner Bros. Pictures',
      imageUrl: '$_duotone/ky0xOc5OrhzkZ1N6KyUxacfQsCk.png',
      kind: 'studio',
      id: 174),
  SeerrCompany(
      name: 'Universal',
      imageUrl: '$_duotone/8lvHyhjr8oUKOOy2dKXoALWKdp0.png',
      kind: 'studio',
      id: 33),
  SeerrCompany(
      name: 'Paramount',
      imageUrl: '$_duotone/fycMZt242LVjagMByZOLUGbCvv3.png',
      kind: 'studio',
      id: 4),
  SeerrCompany(
      name: 'Pixar',
      imageUrl: '$_duotone/1TjvGVDMYsj6JBxOAkUHpPEwLf7.png',
      kind: 'studio',
      id: 3),
  SeerrCompany(
      name: 'Dreamworks',
      imageUrl: '$_duotone/kP7t6RwGz2AvvTkvnI1uteEwHet.png',
      kind: 'studio',
      id: 521),
  SeerrCompany(
      name: 'Marvel Studios',
      imageUrl: '$_duotone/hUzeosd33nzE5MCNsZxCGEKTXaQ.png',
      kind: 'studio',
      id: 420),
  SeerrCompany(
      name: 'DC',
      imageUrl: '$_duotone/2Tc1P3Ac8M479naPp1kYT3izLS5.png',
      kind: 'studio',
      id: 9993),
  SeerrCompany(
      name: 'A24',
      imageUrl: '$_duotone/1ZXsGaFPgrgS6ZZGS37AqD5uU12.png',
      kind: 'studio',
      id: 41077),
];

/// TV networks, in Jellyseerr's order.
const kSeerrNetworks = <SeerrCompany>[
  SeerrCompany(
      name: 'Netflix',
      imageUrl: '$_duotone/wwemzKWzjKYJFfCeiB57q3r4Bcm.png',
      kind: 'network',
      id: 213),
  SeerrCompany(
      name: 'Disney+',
      imageUrl: '$_duotone/gJ8VX6JSu3ciXHuC2dDGAo2lvwM.png',
      kind: 'network',
      id: 2739),
  SeerrCompany(
      name: 'Prime Video',
      imageUrl: '$_duotone/ifhbNuuVnlwYy5oXA5VIb2YR8AZ.png',
      kind: 'network',
      id: 1024),
  SeerrCompany(
      name: 'Apple TV+',
      imageUrl: '$_duotone/4KAy34EHvRM25Ih8wb82AuGU7zJ.png',
      kind: 'network',
      id: 2552),
  SeerrCompany(
      name: 'Hulu',
      imageUrl: '$_duotone/pqUTCleNUiTLAVlelGxUgWn1ELh.png',
      kind: 'network',
      id: 453),
  SeerrCompany(
      name: 'HBO',
      imageUrl: '$_duotone/tuomPhY2UtuPTqqFnKMVHvSb724.png',
      kind: 'network',
      id: 49),
  SeerrCompany(
      name: 'Discovery+',
      imageUrl: '$_duotone/1D1bS3Dyw4ScYnFWTlBOvJXC3nb.png',
      kind: 'network',
      id: 4353),
  SeerrCompany(
      name: 'ABC',
      imageUrl: '$_duotone/ndAvF4JLsliGreX87jAc9GdjmJY.png',
      kind: 'network',
      id: 2),
  SeerrCompany(
      name: 'FOX',
      imageUrl: '$_duotone/1DSpHrWyOORkL9N2QHX7Adt31mQ.png',
      kind: 'network',
      id: 19),
  SeerrCompany(
      name: 'Cinemax',
      imageUrl: '$_duotone/6mSHSquNpfLgDdv6VnOOvC5Uz2h.png',
      kind: 'network',
      id: 359),
  SeerrCompany(
      name: 'AMC',
      imageUrl: '$_duotone/pmvRmATOCaDykE6JrVoeYxlFHw3.png',
      kind: 'network',
      id: 174),
  SeerrCompany(
      name: 'Showtime',
      imageUrl: '$_duotone/Allse9kbjiP6ExaQrnSpIhkurEi.png',
      kind: 'network',
      id: 67),
  SeerrCompany(
      name: 'Starz',
      imageUrl: '$_duotone/8GJjw3HHsAJYwIWKIPBPfqMxlEa.png',
      kind: 'network',
      id: 318),
  SeerrCompany(
      name: 'The CW',
      imageUrl: '$_duotone/ge9hzeaU7nMtQ4PjkFlc68dGAJ9.png',
      kind: 'network',
      id: 71),
  SeerrCompany(
      name: 'NBC',
      imageUrl: '$_duotone/o3OedEP0f9mfZr33jz2BfXOUK5.png',
      kind: 'network',
      id: 6),
  SeerrCompany(
      name: 'CBS',
      imageUrl: '$_duotone/nm8d7P7MJNiBLdgIzUK0gkuEA4r.png',
      kind: 'network',
      id: 16),
  SeerrCompany(
      name: 'Paramount+',
      imageUrl: '$_duotone/fi83B1oztoS47xxcemFdPMhIzK.png',
      kind: 'network',
      id: 4330),
  SeerrCompany(
      name: 'BBC One',
      imageUrl: '$_duotone/mVn7xESaTNmjBUyUtGNvDQd3CT1.png',
      kind: 'network',
      id: 4),
  SeerrCompany(
      name: 'Cartoon Network',
      imageUrl: '$_duotone/c5OC6oVCg6QP4eqzW6XIq17CQjI.png',
      kind: 'network',
      id: 56),
  SeerrCompany(
      name: 'Adult Swim',
      imageUrl: '$_duotone/9AKyspxVzywuaMuZ1Bvilu8sXly.png',
      kind: 'network',
      id: 80),
  SeerrCompany(
      name: 'Nickelodeon',
      imageUrl: '$_duotone/ikZXxg6GnwpzqiZbRPhJGaZapqB.png',
      kind: 'network',
      id: 13),
  SeerrCompany(
      name: 'Peacock',
      imageUrl: '$_duotone/gIAcGTjKKr0KOHL5s4O36roJ8p7.png',
      kind: 'network',
      id: 3353),
];
