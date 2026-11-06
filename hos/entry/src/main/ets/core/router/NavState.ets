import { ChatScenarioDto, ChatSessionDto } from '../net/ChatDtos';
import { StoryMaterialDto } from '../net/StoryDtos';
import { SentenceDto } from '../net/Dtos';

/**
 * 跨页面的入参（替代 NavPathStack 的 param，原因见 NavigationService 注释）。
 *
 * 约定：push 之前由发起方设置，目标页在 aboutToAppear 里读取一次；
 * 不要在页面里改这些静态字段（会被其它页面覆盖）。
 */
export class PracticeTarget {
  sentences: SentenceDto[] = [];
  index: number = 0;
  level: string = 'A1';
  child: boolean = false;
}

export class FlowTarget {
  round: number = 1;
  sentenceIds: string[] = [];
}

export class ChatTarget {
  scenario: ChatScenarioDto | null = null;
  sessionId: string = '';
  includeChild: boolean = false;
}

export class StoryTarget {
  storyId: string = '';
  material: StoryMaterialDto | null = null;
}

export class SessionTarget {
  sessionId: string = '';
  session: ChatSessionDto | null = null;
}

export class NavState {
  static practice: PracticeTarget = new PracticeTarget();
  static flow: FlowTarget = new FlowTarget();
  static chat: ChatTarget = new ChatTarget();
  static story: StoryTarget = new StoryTarget();
  static session: SessionTarget = new SessionTarget();

  static setPractice(sentences: SentenceDto[], index: number, level: string, child: boolean): void {
    const target = new PracticeTarget();
    target.sentences = sentences;
    target.index = index;
    target.level = level;
    target.child = child;
    NavState.practice = target;
  }

  static setChat(scenario: ChatScenarioDto | null, includeChild: boolean): void {
    const target = new ChatTarget();
    target.scenario = scenario;
    target.includeChild = includeChild;
    NavState.chat = target;
  }

  static setStory(storyId: string, material: StoryMaterialDto | null): void {
    const target = new StoryTarget();
    target.storyId = storyId;
    target.material = material;
    NavState.story = target;
  }

  static setSession(sessionId: string): void {
    const target = new SessionTarget();
    target.sessionId = sessionId;
    NavState.session = target;
  }
}
