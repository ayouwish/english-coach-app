/** 路由名常量（docs/architecture.md §4.2）。跨页面跳转只允许用这里的常量。 */
export class Routes {
  static readonly LOGIN: string = 'login';
  static readonly SENTENCES: string = 'sentences';
  static readonly PRACTICE: string = 'practice';
  static readonly SETTINGS: string = 'settings';

  // 连读
  static readonly FLOW: string = 'flow';
  static readonly FLOW_SUMMARY: string = 'flow_summary';

  // 对话
  static readonly CHAT_SCENARIOS: string = 'chat_scenarios';
  static readonly CHAT_SESSION: string = 'chat_session';
  static readonly CHAT_HISTORY: string = 'chat_history';
  static readonly CHAT_DETAIL: string = 'chat_detail';
  static readonly CHAT_CUSTOM: string = 'chat_custom';

  // 故事
  static readonly STORY: string = 'story';
  static readonly STORY_RECORD: string = 'story_record';
  static readonly STORY_DETAIL: string = 'story_detail';
  static readonly STORY_REVIEW: string = 'story_review';

  // 统计 / 家长
  static readonly DIAGNOSIS: string = 'diagnosis';
  static readonly REVIEW: string = 'review';
  static readonly BLIND_TEST: string = 'blind_test';
  static readonly PARENT: string = 'parent';
  static readonly FAMILY: string = 'family';
  static readonly SUGGESTIONS: string = 'suggestions';
  static readonly AVATAR: string = 'avatar';
  static readonly VOICES: string = 'voices';
  static readonly HEALTH: string = 'health';
}
