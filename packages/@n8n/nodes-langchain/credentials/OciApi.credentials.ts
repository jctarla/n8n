import type {
	ICredentialType,
	INodeProperties,
} from 'n8n-workflow';

export class OciApi implements ICredentialType {
	name = 'ociApi';

	displayName = 'Oracle Cloud Infrastructure API';

	documentationUrl = 'oci';

	properties: INodeProperties[] = [
		{
			displayName: 'Compartment ID',
			name: 'compartmentId',
			type: 'string',
			typeOptions: { password: true },
			required: true,
			default: '',
			description: 'OCI compartment OCID where the Generative AI service is available',
		},
		{
			displayName: 'Region',
			name: 'region',
			type: 'options',
			options: [
				{
					name: 'US Ashburn (us-ashburn-1)',
					value: 'us-ashburn-1',
				},
				{
					name: 'US Chicago (us-chicago-1)',
					value: 'us-chicago-1',
				},
				{
					name: 'UK London (uk-london-1)',
					value: 'uk-london-1',
				},
				{
					name: 'Frankfurt (eu-frankfurt-1)',
					value: 'eu-frankfurt-1',
				},
			],
			default: 'us-ashburn-1',
			required: true,
			description: 'OCI region where the Generative AI service is available',
		},
	];
}