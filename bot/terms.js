import { config } from './config.js';
import { panel, payload } from './components.js';

// ===========================================================================
//  이용약관 내용
//
//  아래 항목을 고치면 /이용약관 으로 나가는 글이 바뀝니다.
//  항목을 늘리거나 줄여도 됩니다.
// ===========================================================================
const TERMS = [
  {
    name: '제1조 (목적)',
    value: `이 약관은 ${config.brandName} 가 제공하는 서비스의 이용 조건과 절차를 정합니다.`,
  },
  {
    name: '제2조 (이용)',
    value: [
      '서비스를 이용하면 이 약관에 동의한 것으로 봅니다.',
      '만 14세 미만은 보호자의 동의가 필요합니다.',
    ].join('\n'),
  },
  {
    name: '제3조 (금지 행위)',
    value: [
      '다른 이용자에게 피해를 주는 행위',
      '서비스를 방해하거나 무단으로 접근하는 행위',
      '제품을 무단으로 배포하거나 판매하는 행위',
      '허위 정보를 제공하는 행위',
    ].join('\n'),
  },
  {
    name: '제4조 (제품)',
    value: [
      '제공된 제품의 저작권은 제작자에게 있습니다.',
      '재배포, 재판매, 무단 수정은 금지합니다.',
      '결제 후 제공된 제품은 원칙적으로 환불되지 않습니다.',
    ].join('\n'),
  },
  {
    name: '제5조 (문의)',
    value: [
      '문의는 문의 채널을 통해 접수합니다.',
      '문의 내용은 상담 목적으로 보관될 수 있습니다.',
    ].join('\n'),
  },
  {
    name: '제6조 (책임)',
    value: [
      '이용자의 부주의로 생긴 문제에 대해서는 책임지지 않습니다.',
      '서비스는 사정에 따라 변경되거나 중단될 수 있습니다.',
    ].join('\n'),
  },
  {
    name: '제7조 (약관 변경)',
    value: '약관이 바뀌면 공지 후 적용합니다.',
  },
];

// ===========================================================================
//  A/S 이용약관 내용
//
//  아래 항목을 고치면 /수리약관 으로 나가는 글이 바뀝니다.
//  기간과 횟수는 .env 의 REPAIR_HOURS, REPAIR_FREE_COUNT 로도 바꿀 수 있습니다.
// ===========================================================================
const REPAIR_TERMS = [
  {
    name: '제1조 (목적)',
    value: `이 약관은 ${config.brandName} 가 전달한 제품의 A/S 조건을 정합니다.`,
  },
  {
    name: '제2조 (수리 기간)',
    value: [
      `제작이 끝나고 전달이 끝난 시점부터 ${config.repairHours}시간 안에 수리를 맡길 수 있습니다.`,
      `${config.repairHours}시간이 지나면 무상 수리 대상이 아닙니다.`,
    ].join('\n'),
  },
  {
    name: '제3조 (횟수)',
    value: `무상 수리는 인당 최대 ${config.repairFreeCount}회까지 가능합니다.`,
  },
  {
    name: '제4조 (비용)',
    value: [
      `${config.repairHours}시간이 지났거나 ${config.repairFreeCount}회를 모두 쓴 뒤에는 약간의 비용을 부담해야 합니다.`,
      '비용은 수리 내용에 따라 접수할 때 따로 안내합니다.',
    ].join('\n'),
  },
  {
    name: '제5조 (접수)',
    value: [
      '수리는 문의 채널로 접수합니다.',
      '어떤 문제인지 적어 주시면 확인 후 진행합니다.',
    ].join('\n'),
  },
  {
    name: '제6조 (범위)',
    value: [
      '전달한 제품 자체의 오류를 고치는 것이 A/S 입니다.',
      '새 기능 추가나 처음에 요청하지 않았던 내용의 변경은 A/S 가 아니라 새 작업으로 봅니다.',
      '이용자가 직접 수정한 뒤 생긴 문제는 무상 수리 대상이 아닙니다.',
    ].join('\n'),
  },
  {
    name: '제7조 (약관 변경)',
    value: '약관이 바뀌면 공지 후 적용합니다.',
  },
];

export function buildTermsPayload() {
  const container = panel({
    color: config.colors.primary,
    title: '이용약관',
    description: '서비스를 이용하기 전에 아래 내용을 확인해 주세요.',
    fields: TERMS,
    footer: `${config.brandName} 이용약관`,
  });

  return payload(container);
}

export async function handleTermsCommand(interaction) {
  // 명령을 쓴 채널에 그대로 올립니다.
  await interaction.reply(buildTermsPayload());
}

export function buildRepairTermsPayload() {
  const container = panel({
    color: config.colors.primary,
    title: 'A/S 이용약관',
    description: '수리를 맡기기 전에 아래 내용을 확인해 주세요.',
    fields: REPAIR_TERMS,
    footer: `${config.brandName} A/S`,
  });

  return payload(container);
}

export async function handleRepairTermsCommand(interaction) {
  await interaction.reply(buildRepairTermsPayload());
}
