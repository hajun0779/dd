import { PermissionsBitField } from 'discord.js';

import { config } from './config.js';

/**
 * 명령어마다 누가 쓸 수 있는지 정합니다.
 *
 * 기본값은 아래 표에 있고, .env 의 COMMAND_ROLES 로 명령마다 역할을 정하면
 * 그 역할만 있어도 쓸 수 있습니다.
 *
 *   COMMAND_ROLES=송금요청:1111,배당:2222/3333
 *
 * 서버 관리자와 총관리자 역할은 언제나 모든 명령을 쓸 수 있습니다.
 */

// everyone: 누구나 / staff: 서버 관리 권한 / admin: 총관리자만
export const COMMAND_ACCESS = {
  티켓패널: 'staff',
  문의안내: 'staff',
  문의안내추가: 'staff',
  문의안내삭제: 'staff',
  이용약관: 'staff',
  수리약관: 'staff',
  채용공고: 'staff',
  초대코드: 'everyone',
  초대랭킹: 'everyone',
  직원명단: 'staff',
  직원명단설정: 'staff',
  파트너쉽: 'staff',
  제품설정: 'staff',
  제품전송: 'staff',
  분야설정: 'staff',
  배당: 'staff',
  수리: 'staff',
  급여지급: 'staff',
  지급상태: 'staff',
  송금요청: 'admin',
};

export function accessOf(commandName) {
  return COMMAND_ACCESS[commandName] ?? 'staff';
}

/** 이 명령에 따로 정해 둔 역할 */
export function rolesFor(commandName) {
  return config.commandRoles?.[commandName] ?? [];
}

/**
 * 명령을 목록에서 숨길지 정합니다.
 *
 * 역할을 따로 정한 명령은 그 역할에게 보여야 하는데, 디스코드는 기본 노출을
 * 권한 단위로만 정할 수 있습니다. 그래서 역할을 정한 명령은 모두에게 보이게 두고
 * 실제 판정은 봇이 합니다.
 */
export function hidesByDefault(commandName) {
  if (rolesFor(commandName).length > 0) return false;
  return accessOf(commandName) !== 'everyone';
}

export function isAdminMember(member) {
  if (!member) return false;
  if (member.permissions?.has?.(PermissionsBitField.Flags.Administrator)) return true;
  if (!config.adminRoleId) return false;
  return Boolean(member.roles?.cache?.has(config.adminRoleId));
}

export function canUseCommand(member, commandName) {
  if (!member) return false;

  // 서버 관리자와 총관리자는 언제나 쓸 수 있습니다.
  if (isAdminMember(member)) return true;

  const roles = rolesFor(commandName);
  if (roles.length > 0) {
    return roles.some((roleId) => member.roles?.cache?.has(roleId));
  }

  const access = accessOf(commandName);
  if (access === 'everyone') return true;
  if (access === 'admin') return false; // 총관리자만. 위에서 이미 걸렀습니다.
  return Boolean(member.permissions?.has?.(PermissionsBitField.Flags.ManageGuild));
}

/** 못 쓰는 이유를 알려 줍니다. */
export function deniedReason(commandName) {
  const roles = rolesFor(commandName);
  if (roles.length > 0) {
    return `${roles.map((id) => `<@&${id}>`).join(' ')} 역할을 가진 사람만 쓸 수 있습니다.`;
  }

  if (accessOf(commandName) === 'admin') {
    return config.adminRoleId
      ? `<@&${config.adminRoleId}> 역할을 가진 사람만 쓸 수 있습니다.`
      : '총관리자 역할이 설정되지 않았습니다. .env 의 ADMIN_ROLE_ID 를 채워 주세요.';
  }

  return '서버 관리 권한이 있어야 쓸 수 있습니다.';
}
