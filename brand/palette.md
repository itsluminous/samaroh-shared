# Samaroh Brand Palette

Shared color tokens for both clients. On Android 12+ the app prefers **dynamic color**
(Material You); everywhere else (older Android, web) it uses this curated fallback palette
built around primary deep purple `#6750A4` — bookings render in purple to match the
calendar mental model users already have.

## Core seed

| Token | Value |
|---|---|
| `seed` | `#6750A4` |

## Light scheme

| Token | Value | Usage |
|---|---|---|
| `primary` | `#6750A4` | Buttons, FAB, active nav item, confirmed-booking pills |
| `onPrimary` | `#FFFFFF` | Text/icons on primary |
| `primaryContainer` | `#EADDFF` | Tonal buttons, selected chips |
| `onPrimaryContainer` | `#21005D` | Text on primaryContainer |
| `secondary` | `#625B71` | Secondary actions, filter chips |
| `onSecondary` | `#FFFFFF` | Text on secondary |
| `secondaryContainer` | `#E8DEF8` | Nav indicator, secondary containers |
| `onSecondaryContainer` | `#1D192B` | Text on secondaryContainer |
| `tertiary` | `#7D5260` | Accents, highlights |
| `onTertiary` | `#FFFFFF` | Text on tertiary |
| `tertiaryContainer` | `#FFD8E4` | Confirmed-booking calendar pill fill |
| `onTertiaryContainer` | `#31111D` | Text on tertiaryContainer |
| `error` | `#B3261E` | Errors, overdue/due amounts |
| `onError` | `#FFFFFF` | Text on error |
| `errorContainer` | `#F9DEDC` | Error surfaces |
| `onErrorContainer` | `#410E0B` | Text on errorContainer |
| `background` | `#FFFBFE` | Screen background |
| `onBackground` | `#1C1B1F` | Body text |
| `surface` | `#FFFBFE` | Cards, sheets |
| `onSurface` | `#1C1B1F` | Text on surface |
| `surfaceVariant` | `#E7E0EC` | Blocked-date stripes, dividers' base |
| `onSurfaceVariant` | `#49454F` | Secondary text, icons |
| `outline` | `#79747E` | Field borders, tentative-booking pill outline |

## Dark scheme

| Token | Value |
|---|---|
| `primary` | `#D0BCFF` |
| `onPrimary` | `#381E72` |
| `primaryContainer` | `#4F378B` |
| `onPrimaryContainer` | `#EADDFF` |
| `secondary` | `#CCC2DC` |
| `onSecondary` | `#332D41` |
| `secondaryContainer` | `#4A4458` |
| `onSecondaryContainer` | `#E8DEF8` |
| `tertiary` | `#EFB8C8` |
| `onTertiary` | `#492532` |
| `tertiaryContainer` | `#633B48` |
| `onTertiaryContainer` | `#FFD8E4` |
| `error` | `#F2B8B5` |
| `onError` | `#601410` |
| `errorContainer` | `#8C1D18` |
| `onErrorContainer` | `#F9DEDC` |
| `background` | `#1C1B1F` |
| `onBackground` | `#E6E1E5` |
| `surface` | `#1C1B1F` |
| `onSurface` | `#E6E1E5` |
| `surfaceVariant` | `#49454F` |
| `onSurfaceVariant` | `#CAC4D0` |
| `outline` | `#938F99` |

## Semantic (both schemes)

| Token | Light | Dark | Usage |
|---|---|---|---|
| `moneyIn` | `#146C2E` | `#6DD58C` | "You got" / received amounts |
| `moneyOut` | `#B3261E` | `#F2B8B5` | "You gave" / due amounts |
| `tentative` | `#7A5900` | `#F7BD48` | Tentative-booking amber (outlined pill) |

## Calendar status mapping

| State | Rendering |
|---|---|
| Confirmed booking | Filled `tertiaryContainer` pill, `onTertiaryContainer` text |
| Tentative booking | Outlined pill, `tentative` outline + text |
| Cancelled booking | Hidden from calendar (strikethrough in list views) |
| Date block | Grey stripes on `surfaceVariant` |
| Today | `primary` outline ring |
