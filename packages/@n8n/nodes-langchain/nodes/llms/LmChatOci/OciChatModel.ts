import { BaseChatModel } from '@langchain/core/language_models/chat_models';
import { BaseMessage, AIMessage, HumanMessage, SystemMessage } from '@langchain/core/messages';
import { ChatResult } from '@langchain/core/outputs';
import { CallbackManagerForLLMRun } from '@langchain/core/callbacks/manager';
import { GenerativeAiInferenceClient, models, requests } from 'oci-generativeaiinference';
import { InstancePrincipalsAuthenticationDetailsProviderBuilder } from 'oci-common';

interface OciChatModelOptions {
	compartmentId: string;
	region: string;
	modelId?: string;
	temperature?: number;
	maxTokens?: number;
	topP?: number;
	topK?: number;
	frequencyPenalty?: number;
	presencePenalty?: number;
}

export class OciChatModel extends BaseChatModel {
	lc_serializable = true;
	lc_namespace = ['langchain', 'llms', 'oci'];

	private client!: GenerativeAiInferenceClient;
	private compartmentId: string;
	private modelId: string;
	private temperature: number;
	private maxTokens: number;
	private topP: number;
	private topK: number;
	private frequencyPenalty: number;
	private presencePenalty: number;

	constructor(options: OciChatModelOptions) {
		super({});
		
		this.compartmentId = options.compartmentId;
		this.modelId = options.modelId || 'ocid1.generativeaimodel.oc1.iad.amaaaaaask7dceya6pk3sxishpiexm2rb5sf4ytb5tsbz4to2g3g23smidaa';
		this.temperature = options.temperature ?? 0.7;
		this.maxTokens = options.maxTokens ?? 2048;
		this.topP = options.topP ?? 1;
		this.topK = options.topK ?? 0;
		this.frequencyPenalty = options.frequencyPenalty ?? 0;
		this.presencePenalty = options.presencePenalty ?? 0;
		
		this.initializeClient(options.region);
	}

	private async initializeClient(region: string) {
		const provider = await new InstancePrincipalsAuthenticationDetailsProviderBuilder().build();
		
		this.client = new GenerativeAiInferenceClient({
			authenticationDetailsProvider: provider,
		});

		this.client.endpoint = `https://inference.generativeai.${region}.oci.oraclecloud.com`;
	}

	_llmType(): string {
		return 'oci-chat';
	}

	_identifyingParams() {
		return {
			compartmentId: this.compartmentId,
			modelId: this.modelId,
			temperature: this.temperature,
			maxTokens: this.maxTokens,
			topP: this.topP,
			topK: this.topK,
		};
	}

	private convertMessagesToOciFormat(messages: BaseMessage[]): any[] {
		return messages.map((message) => {
			let role: string;
			if (message instanceof HumanMessage) {
				role = 'USER';
			} else if (message instanceof AIMessage) {
				role = 'ASSISTANT';
			} else if (message instanceof SystemMessage) {
				role = 'SYSTEM';
			} else {
				role = 'USER';
			}

			return {
				role,
				content: [
					{
						type: 'TEXT',
						text: message.content as string,
					},
				],
			};
		});
	}

	async _generate(
		messages: BaseMessage[],
		_options?: this['ParsedCallOptions'],
		_runManager?: CallbackManagerForLLMRun,
	): Promise<ChatResult> {
		const servingMode: models.OnDemandServingMode = {
			modelId: this.modelId,
			servingType: 'ON_DEMAND',
		};

		const chatRequest: requests.ChatRequest = {
			chatDetails: {
				compartmentId: this.compartmentId,
				servingMode: servingMode,
				chatRequest: {
					messages: this.convertMessagesToOciFormat(messages),
					apiFormat: 'GENERIC',
					maxTokens: this.maxTokens,
					temperature: this.temperature,
					frequencyPenalty: this.frequencyPenalty,
					presencePenalty: this.presencePenalty,
					topK: this.topK,
					topP: this.topP,
				},
			},
		};

		try {
			const response = await this.client.chat(chatRequest);
			
			// Based on OCI SDK structure, the response is directly the chat response
			if (!response) {
				throw new Error('No response received from OCI Generative AI');
			}

			// The response object contains the chat result directly
			const chatResult = (response as any).chatResponse?.chatResult;
			if (!chatResult?.response) {
				throw new Error('No valid response in OCI Generative AI result');
			}

			const content = chatResult.response;
			const message = new AIMessage(content);

			// Extract token usage if available
			const tokenUsage = {
				completionTokens: 0, // OCI doesn't provide detailed token counts
				promptTokens: 0,
				totalTokens: 0,
			};

			return {
				generations: [
					{
						text: content,
						message,
					},
				],
				llmOutput: {
					tokenUsage,
					modelVersion: chatResult.modelVersion || 'unknown',
				},
			};
		} catch (error) {
			throw new Error(`OCI Generative AI API error: ${error}`);
		}
	}
}