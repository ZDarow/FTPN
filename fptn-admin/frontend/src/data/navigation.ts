import {
  Bot,
  LayoutDashboard,
  Server,
  Users,
  type LucideIcon
} from 'lucide-react'

type NavChild = {
  id: string
  labelKey: string
  href: string
}

type NavLinkItem = {
  type: 'link'
  id: string
  labelKey: string
  href: string
  icon: LucideIcon
}

type NavMenuItem = {
  type: 'menu'
  id: string
  labelKey: string
  icon: LucideIcon
  children: NavChild[]
}

type NavCategoryItem = {
  type: 'category'
  labelKey: string
}

export type NavItem = NavCategoryItem | NavLinkItem | NavMenuItem

export const navigation: NavItem[] = [
  {
    type: 'link',
    id: 'dashboard',
    labelKey: 'nav.dashboard',
    href: '/',
    icon: LayoutDashboard
  },
  {
    type: 'link',
    id: 'users',
    labelKey: 'nav.users',
    href: '/users',
    icon: Users
  },
  {
    type: 'link',
    id: 'servers',
    labelKey: 'nav.servers',
    href: '/servers',
    icon: Server
  },
  {
    type: 'link',
    id: 'telegram-bot',
    labelKey: 'nav.telegramBot',
    href: '/telegram-bot',
    icon: Bot
  }
]
