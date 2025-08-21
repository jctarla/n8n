import {
	NodeConnectionTypes,
	type INodeType,
	type INodeTypeDescription,
	type ISupplyDataFunctions,
	type SupplyData,
} from 'n8n-workflow';

import { getConnectionHintNoticeField } from '@utils/sharedFields';

import { N8nLlmTracing } from '../N8nLlmTracing';
import { OciChatModel } from './OciChatModel';

export class LmChatOci implements INodeType {
	description: INodeTypeDescription = {
		displayName: 'Oracle Cloud Infrastructure Chat Model',
		name: 'lmChatOci',
		icon: 'file:oci.svg',
		group: ['transform'],
		version: [1],
		description: 'For advanced usage with an AI chain',
		defaults: {
			name: 'Oracle Cloud Infrastructure Chat Model',
		},
		codex: {
			categories: ['AI'],
			subcategories: {
				AI: ['Language Models', 'Root Nodes'],
				'Language Models': ['Chat Models (Recommended)'],
			},
			resources: {
				primaryDocumentation: [
					{
						url: 'https://docs.oracle.com/en-us/iaas/Content/generative-ai/overview.htm',
					},
				],
			},
		},
		inputs: [],
		outputs: [NodeConnectionTypes.AiLanguageModel],
		outputNames: ['Model'],
		credentials: [
			{
				name: 'ociApi',
				required: true,
			},
		],
		properties: [
			getConnectionHintNoticeField([NodeConnectionTypes.AiChain, NodeConnectionTypes.AiAgent]),
			{
				displayName: 'Model',
				name: 'model',
				type: 'options',
				description: 'The model which will generate the completion',
				options: [
					{
						name: 'Meta Llama 3.1 405B Instruct',
						value: 'ocid1.generativeaimodel.oc1.iad.amaaaaaask7dceya6pk3sxishpiexm2rb5sf4ytb5tsbz4to2g3g23smidaa',
					},
					{
						name: 'Meta Llama 3.1 70B Instruct',
						value: 'ocid1.generativeaimodel.oc1.iad.amaaaaaa23dgkeya6pk3sxishpiexm2rb5sf4ytb5tsbz4to2g3g23smidaa',
					},
					{
						name: 'Cohere Command R+',
						value: 'ocid1.generativeaimodel.oc1.iad.amaaaaaask7dceybpn7wl7kkisl4mfe7v5mgcq4juqlvfchcjp7nt5xxf2fka',
					},
					{
						name: 'Cohere Command R',
						value: 'ocid1.generativeaimodel.oc1.iad.amaaaaaask7dceyb4oegfzv6sk4l6xmf7v5mgcq4juqlvfchcjp7nt5xxf2fka',
					},
				],
				default: 'ocid1.generativeaimodel.oc1.iad.amaaaaaask7dceya6pk3sxishpiexm2rb5sf4ytb5tsbz4to2g3g23smidaa',
			},
			{
				displayName: 'Options',
				name: 'options',
				placeholder: 'Add Option',
				description: 'Additional options to add',
				type: 'collection',
				default: {},
				options: [
					{
						displayName: 'Frequency Penalty',
						name: 'frequencyPenalty',
						default: 0,
						typeOptions: { maxValue: 2, minValue: 0, numberPrecision: 1 },
						description:
							'Positive values penalize new tokens based on their existing frequency in the text so far',
						type: 'number',
					},
					{
						displayName: 'Maximum Number of Tokens',
						name: 'maxTokens',
						default: 2048,
						description: 'The maximum number of tokens to generate in the completion',
						type: 'number',
						typeOptions: {
							maxValue: 4096,
							minValue: 1,
						},
					},
					{
						displayName: 'Presence Penalty',
						name: 'presencePenalty',
						default: 0,
						typeOptions: { maxValue: 2, minValue: 0, numberPrecision: 1 },
						description:
							'Positive values penalize new tokens based on whether they appear in the text so far',
						type: 'number',
					},
					{
						displayName: 'Sampling Temperature',
						name: 'temperature',
						default: 0.7,
						typeOptions: { maxValue: 1, minValue: 0, numberPrecision: 1 },
						description:
							'Controls randomness: Lowering results in less random completions. As the temperature approaches zero, the model will become deterministic and repetitive.',
						type: 'number',
					},
					{
						displayName: 'Top K',
						name: 'topK',
						default: 0,
						typeOptions: { maxValue: 500, minValue: 0 },
						description:
							'Limits the number of tokens to consider for each step, where 0 means no limit',
						type: 'number',
					},
					{
						displayName: 'Top P',
						name: 'topP',
						default: 1,
						typeOptions: { maxValue: 1, minValue: 0, numberPrecision: 2 },
						description:
							'Controls diversity via nucleus sampling: 0.5 means half of all likelihood-weighted options are considered',
						type: 'number',
					},
				],
			},
		],
	};

	async supplyData(this: ISupplyDataFunctions, itemIndex: number): Promise<SupplyData> {
		const credentials = await this.getCredentials<{
			compartmentId: string;
			region: string;
		}>('ociApi');

		const modelId = this.getNodeParameter('model', itemIndex) as string;

		const options = this.getNodeParameter('options', itemIndex, {}) as {
			frequencyPenalty?: number;
			maxTokens?: number;
			presencePenalty?: number;
			temperature?: number;
			topK?: number;
			topP?: number;
		};

		const model = new OciChatModel({
			compartmentId: credentials.compartmentId,
			region: credentials.region,
			modelId,
			temperature: options.temperature,
			maxTokens: options.maxTokens,
			topP: options.topP,
			topK: options.topK,
			frequencyPenalty: options.frequencyPenalty,
			presencePenalty: options.presencePenalty,
		});

		// Add tracing
		model.callbacks = [new N8nLlmTracing(this)];

		return {
			response: model,
		};
	}
}